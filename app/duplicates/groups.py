"""Duplicate and similar-scene groups on the collection index (brief section 5).

Categories:
  exact          identical bytes (same SHA-256)
  near           visually near-identical: signature similarity >= 0.92, or >= 0.80
                 within a 3 s burst of the same device, or >= 0.80 confirmed by
                 ORB geometry
  similar_scene  looks alike (signature >= 0.80) but not confirmed: keep both
Only exact and near groups get a recommended keeper. Nothing is deleted or
moved; the owner can override the keeper and the choice survives re-analysis.
"""
from __future__ import annotations

import json
from collections import defaultdict
from typing import Callable, Optional

import numpy as np

from app.collections import now_iso
from app.duplicates.visual import scene_match, signature_and_sharpness, unpack

NEAR_SIG = 0.92
CANDIDATE_SIG = 0.80
BURST_SIG = 0.85
BURST_S = 3.0
BLOCK = 1000
LONG_GROUP = 6


def _split_chains(members, rows, sigs):
    """Union-find chains frames that each resemble only their neighbour. Walk the
    group in time order and start a new subgroup whenever a frame no longer
    resembles the subgroup's first frame, so a long sequence is not one group."""
    if sigs is None or len(members) < 3:
        return [members]
    out, cur = [], [members[0]]
    for m in members[1:]:
        first = cur[0]
        same = rows[m]['sha256'] == rows[first]['sha256']
        sim = 1 - np.count_nonzero(sigs[m] != sigs[first]) / sigs.shape[1]
        if same or sim >= CANDIDATE_SIG:
            cur.append(m)
        else:
            out.append(cur)
            cur = [m]
    out.append(cur)
    return [g for g in out if len(g) > 1]


class _UF:
    def __init__(self):
        self.p = {}

    def find(self, x):
        self.p.setdefault(x, x)
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def _assets(conn):
    return conn.execute(
        "SELECT a.id, a.sha256, a.width, a.height, a.rel_path, a.source_id, a.make, a.model, "
        "s.path || '/' || a.rel_path AS path, c.sort_key + COALESCE(cc.applied_s, 0) AS t "
        "FROM assets a JOIN sources s ON s.id = a.source_id "
        "LEFT JOIN capture_time c ON c.asset_id = a.id "
        "LEFT JOIN clocks k ON k.source_id = a.source_id AND k.make = COALESCE(a.make, '') "
        "  AND k.model = COALESCE(a.model, '') "
        "LEFT JOIN clock_corrections cc ON cc.clock_id = k.id "
        "WHERE a.status = 'present' AND a.kind = 'image' AND a.sha256 != '' "
        "ORDER BY t, a.source_id, a.rel_path").fetchall()


def compute_features(conn, progress: Optional[Callable] = None,
                     cancelled: Callable[[], bool] = lambda: False, shas: Optional[set] = None) -> int:
    """Visual signatures of every photo without one (`shas`: only these, M13 per-day pipeline)."""
    rows = _assets(conn)
    if shas is not None:
        rows = [r for r in rows if r['sha256'] in shas]
    have = {r[0] for r in conn.execute('SELECT sha256 FROM visual_features')}
    todo, seen = [], set()
    for r in rows:
        if r['sha256'] not in have and r['sha256'] not in seen:
            seen.add(r['sha256'])
            todo.append(r)
    for i, r in enumerate(todo):
        if cancelled():
            break
        if progress:
            progress(f'Visual signatures: {r["rel_path"]}', i, len(todo))
        res = signature_and_sharpness(r['path'])
        if res is None:
            continue
        with conn:
            conn.execute('INSERT OR REPLACE INTO visual_features (sha256, sig, sharpness, computed_at) '
                         'VALUES (?, ?, ?, ?)', (r['sha256'], res[0], res[1], now_iso()))
    return len(todo)


def build_groups(conn, progress: Optional[Callable] = None,
                 cancelled: Callable[[], bool] = lambda: False, day: Optional[str] = None,
                 day_of: Optional[dict] = None) -> dict:
    """Moments of the whole album, or (M13 per-day pipeline) of one local day: with `day` only that day's
    photos are compared and only the groups holding one of them are replaced; the other days stay as they are.
    A moment never spans two days in the per-day pipeline. `day_of` (asset id -> day) saves a query.
    A cancelled day run stores nothing (the day is built again on resume)."""
    rows = _assets(conn)
    day_ids = None
    if day is not None:
        if day_of is None:
            from app.timeline.event_detector import asset_days
            day_of = asset_days(conn)
        day_ids = {aid for aid, d in day_of.items() if d == day}
        rows = [r for r in rows if r['id'] in day_ids]
    feats = {r['sha256']: (r['sig'], r['sharpness'])
             for r in conn.execute('SELECT sha256, sig, sharpness FROM visual_features')}
    rows = [r for r in rows if r['sha256'] in feats]
    n = len(rows)
    near, similar = _UF(), _UF()
    evidence = defaultdict(list)          # frozenset(pair) -> reasons

    # Exact copies.
    by_sha = defaultdict(list)
    for i, r in enumerate(rows):
        by_sha[r['sha256']].append(i)
    for idxs in by_sha.values():
        for j in idxs[1:]:
            near.union(idxs[0], j)
            evidence[frozenset((idxs[0], j))].append('identical bytes (SHA-256)')

    if n > 1:
        sigs = np.stack([unpack(feats[r['sha256']][0]) for r in rows])
        clock = [(r['source_id'], r['make'] or '', r['model'] or '') for r in rows]
        checked = 0
        for start in range(0, n, BLOCK):
            if cancelled():
                break
            block = similarity_matrix_block(sigs, start, min(n, start + BLOCK))
            ii, jj = np.nonzero(block >= CANDIDATE_SIG)
            for bi, j in zip(ii, jj):
                i = start + bi
                if j <= i or rows[i]['sha256'] == rows[j]['sha256']:
                    continue
                s = float(block[bi, j])
                key = frozenset((i, j))
                dt = abs((rows[i]['t'] or 0) - (rows[j]['t'] or 0))
                if s >= NEAR_SIG:
                    near.union(i, j); evidence[key].append(f'signature similarity {s:.2f}')
                elif clock[i] == clock[j] and dt <= BURST_S and s >= BURST_SIG:
                    near.union(i, j); evidence[key].append(f'burst: {dt:.1f} s apart, similarity {s:.2f}')
                else:
                    checked += 1
                    if progress and checked % 20 == 0:
                        progress('Confirming near duplicates', checked, 0)
                    good, inl = scene_match(rows[i]['path'], rows[j]['path'])
                    if good >= 40 and inl >= 0.5 * good:
                        near.union(i, j)
                        evidence[key].append(f'similarity {s:.2f}, ORB confirmed ({inl} of {good} matches)')
                    else:
                        similar.union(i, j)
                        evidence[key].append(f'similarity {s:.2f}, not confirmed: likely a different shot')

    if day is not None and cancelled():
        return {'cancelled': True}
    groups = []
    sig_arr = sigs if n > 1 else None
    for uf, category in ((near, None), (similar, 'similar_scene')):
        comps = defaultdict(list)
        for x in list(uf.p):
            comps[uf.find(x)].append(x)
        for members in comps.values():
            if len(members) < 2:
                continue
            if category == 'similar_scene' and all(near.find(m) == near.find(members[0]) for m in members):
                continue        # already one duplicate group
            members = sorted(members, key=lambda m: ((rows[m]['t'] or 0), rows[m]['id']))
            parts = [members] if category else _split_chains(members, rows, sig_arr)
            for part in parts:
                cat = category or ('exact' if len({rows[m]['sha256'] for m in part}) == 1 else 'near')
                groups.append((cat, part))

    choices, face_map, qual, verdicts, kw, left_out = _keeper_context(conn, rows, groups)
    with conn:
        if day_ids is None:
            conn.execute('DELETE FROM duplicate_groups')
        else:
            ids = sorted(day_ids)
            for i in range(0, len(ids), 500):
                part = ids[i:i + 500]
                conn.execute('DELETE FROM duplicate_groups WHERE id IN (SELECT group_id FROM duplicate_members '
                             f'WHERE asset_id IN ({",".join("?" * len(part))}))', part)
        counts = defaultdict(int)
        for cat, members in groups:
            key = f'{cat}:' + ','.join(sorted(rows[m]['sha256'] for m in members))
            if cat == 'similar_scene':
                keeper, reasons = None, ['different shots of the same scene: keep both']
            else:
                info = {}
                # A frame the owner left out is never recommended; otherwise the moment would vanish
                # from the export (the keeper is left out, the others are extra frames).
                kept = [m for m in members if rows[m]['sha256'] not in left_out] or members
                keeper, reasons = _recommend(rows, feats, kept, cat, choices.get(key), face_map, qual, kw, info,
                                             verdicts)
            pair_notes = sorted({e for a in members for b in members if a < b
                                 for e in evidence.get(frozenset((a, b)), [])})
            cur = conn.execute('INSERT INTO duplicate_groups (group_key, category, keeper_id, reasons_json) '
                               'VALUES (?, ?, ?, ?)',
                               (key, cat, keeper, json.dumps({'keeper': reasons, 'evidence': pair_notes[:12],
                                                              'margin': info.get('margin'),
                                                              'all_bad': bool(info.get('all_bad'))}
                                                             if cat != 'similar_scene'
                                                             else {'keeper': reasons, 'evidence': pair_notes[:12]},
                                                             ensure_ascii=False)))
            gid = cur.lastrowid
            for m in members:
                conn.execute('INSERT INTO duplicate_members (group_id, asset_id, score) VALUES (?, ?, ?)',
                             (gid, rows[m]['id'], feats[rows[m]['sha256']][1]))
            counts[cat] += 1
    return dict(counts)


def _keeper_context(conn, rows, groups):
    """What the keeper choice reads: owner choices, face summaries per moment, quality, focus verdicts,
    keeper weights and left-out photos. `groups`: [(category, [row index])]."""
    choices = {r['group_key']: r['sha256'] for r in conn.execute('SELECT group_key, sha256 FROM keeper_choices')}
    from app import settings
    from app.quality.faces import summaries, vision_info
    from app.quality.scoring import focus_tiers
    # Eye states compare a face with the same face in the other frames of the moment being built now.
    face_map = summaries(conn, [[rows[m]['sha256'] for m in members] for cat, members in groups
                                if cat != 'similar_scene'])
    qual = {}
    for r in conn.execute('SELECT sha256, region_sharpness, scores_json FROM quality'):
        qual[r['sha256']] = (r['region_sharpness'], json.loads(r['scores_json']).get('aesthetic'))
    vision = vision_info(conn)
    verdicts = {}
    sha_by_id = {r['id']: r['sha256'] for r in rows}
    for aid, t in focus_tiers(conn).items():
        if aid in sha_by_id:
            v = vision.get(sha_by_id[aid]) or {}
            verdicts[sha_by_id[aid]] = {'blur': t['tier'], 'sharpness': t.get('subject_sharpness'),
                                        'aesthetic': v.get('aesthetic')}
    kw = settings.load().get('keeper_weights')
    left_out = {r[0] for r in conn.execute('SELECT sha256 FROM marks WHERE rejected = 1')}
    return choices, face_map, qual, verdicts, kw, left_out


def refresh_keepers(conn) -> list:
    """Choose the keeper of every stored exact/near moment again from the current data, without comparing
    any photos (M13). Focus verdicts are relative to the whole album, so after later days are read an earlier
    day's best frame can change; an owner's keeper choice or a left-out frame too. Returns the ids of the
    groups whose keeper changed."""
    rows = _assets(conn)
    idx = {r['id']: i for i, r in enumerate(rows)}
    feats = {r['sha256']: (r['sig'], r['sharpness'])
             for r in conn.execute('SELECT sha256, sig, sharpness FROM visual_features')}
    stored = conn.execute("SELECT id, group_key, category, keeper_id, reasons_json FROM duplicate_groups "
                          "WHERE category IN ('exact', 'near') ORDER BY id").fetchall()
    members = defaultdict(list)
    for r in conn.execute('SELECT group_id, asset_id FROM duplicate_members'):
        if r['asset_id'] in idx:
            members[r['group_id']].append(idx[r['asset_id']])
    groups = []
    for g in stored:
        ms = sorted(members.get(g['id'], []), key=lambda m: ((rows[m]['t'] or 0), rows[m]['id']))
        if len(ms) > 1 and all(rows[m]['sha256'] in feats for m in ms):
            groups.append((g, ms))
    choices, face_map, qual, verdicts, kw, left_out = _keeper_context(
        conn, rows, [(g['category'], ms) for g, ms in groups])
    changed = []
    with conn:
        for g, ms in groups:
            info = {}
            kept = [m for m in ms if rows[m]['sha256'] not in left_out] or ms
            keeper, reasons = _recommend(rows, feats, kept, g['category'], choices.get(g['group_key']), face_map,
                                         qual, kw, info, verdicts)
            old = json.loads(g['reasons_json'])
            new = {'keeper': reasons, 'evidence': old.get('evidence', []), 'margin': info.get('margin'),
                   'all_bad': bool(info.get('all_bad'))}
            if keeper != g['keeper_id'] or new != old:
                conn.execute('UPDATE duplicate_groups SET keeper_id = ?, reasons_json = ? WHERE id = ?',
                             (keeper, json.dumps(new, ensure_ascii=False), g['id']))
                if keeper != g['keeper_id']:
                    changed.append(g['id'])
    return changed


def similarity_matrix_block(sigs: np.ndarray, start: int, stop: int) -> np.ndarray:
    x = sigs.astype(np.float32)
    blk = x[start:stop]
    agree = blk @ x.T + (1 - blk) @ (1 - x).T
    return agree / sigs.shape[1]


CLEAR_MARGIN = 0.12      # score lead of the best frame (share of the used weight) for an automatic decision


def _problems(sha, faces, verdicts):
    """(closed eyes on a main face, blurry subject) for one frame."""
    f = faces.get(sha) or {}
    v = verdicts.get(sha) or {}
    return bool(f.get('eyes_closed')), v.get('blur') == 'blurry'


def _recommend(rows, feats, members, cat, chosen_sha, faces=None, quality=None, weights=None, info=None,
               verdicts=None):
    """Pick the keeper (M10b order): no closed eyes on a main face first ("unsure" is neutral), then no
    blurry subject, then the weighted blend of the criteria (weights from settings 'keeper_weights'):
    faces  eye state, looking at the camera and Apple's face capture quality
    focus  subject sharpness (bokeh is not a fault); region sharpness when a frame has no subject measure
    look   Apple's aesthetics score; the ranking's overall look when a frame has none
    resolution
    A weight of 0 also switches its first-order check off (faces: eyes, focus: blur). A criterion missing for
    the whole group is left out. `info` (optional dict) receives 'margin' (the best frame's lead over the
    second, 0-1) and 'all_bad' (every frame has closed eyes on a main face or a blurry subject).
    `verdicts`: sha256 -> {blur, sharpness, aesthetic}."""
    info = info if info is not None else {}
    faces, quality, verdicts = faces or {}, quality or {}, verdicts or {}
    sha = {m: rows[m]['sha256'] for m in members}
    probs = {m: _problems(sha[m], faces, verdicts) for m in members}
    info['all_bad'] = cat == 'near' and len(members) > 1 and all(a or b for a, b in probs.values())
    if chosen_sha:
        for m in members:
            if rows[m]['sha256'] == chosen_sha:
                info['margin'] = 1.0
                return rows[m]['id'], ['chosen by you']
    if cat == 'exact':
        info['margin'] = 1.0
        m = min(members, key=lambda m: (rows[m]['source_id'], rows[m]['rel_path']))
        return rows[m]['id'], ['identical files: any copy is the same; suggested the first source\'s copy']
    w = {'faces': 40, 'focus': 30, 'look': 20, 'resolution': 10, **(weights or {})}
    subj = {m: (verdicts.get(sha[m]) or {}).get('sharpness') for m in members}
    aes = {m: (verdicts.get(sha[m]) or {}).get('aesthetic') for m in members}
    crit = {
        'faces': {m: (faces.get(sha[m]) or {}).get('score') for m in members},
        'focus': (subj if all(v is not None for v in subj.values())
                  else {m: (quality.get(sha[m]) or (feats[sha[m]][1],))[0] for m in members}),
        'look': ({m: (aes[m] + 1) / 2 for m in members} if all(v is not None for v in aes.values())
                 else {m: (quality.get(sha[m]) or (None, None))[1] for m in members}),
        'resolution': {m: (rows[m]['width'] or 0) * (rows[m]['height'] or 0) for m in members},
    }
    total = {m: 0.0 for m in members}
    used = 0.0
    for name, vals in crit.items():
        known = [v for v in vals.values() if v is not None]
        if not known or w.get(name, 0) <= 0 or len(set(known)) == 1:
            continue
        hi = max(known) or 1
        used += w[name]
        for m in members:
            total[m] += w[name] * ((vals[m] or 0) / hi)

    def first(m):
        closed, blurry = probs[m]
        return (not (closed and w.get('faces', 0) > 0), not (blurry and w.get('focus', 0) > 0))
    order = sorted(members, key=lambda m: (first(m), total[m], -rows[m]['id']), reverse=True)
    best = order[0]
    margin = round((total[best] - total[order[1]]) / used, 3) if used and len(order) > 1 else 0.0
    if len(order) > 1 and first(best) > first(order[1]):
        margin = max(margin, CLEAR_MARGIN)     # a frame without the problem the others have is a clear choice
    info['margin'] = margin
    reasons = []
    fb = faces.get(sha[best])
    others = [faces.get(sha[m]) for m in members if m != best and faces.get(sha[m])]
    if fb:
        unsure = (fb.get('eyes') or {}).get('unsure', 0)
        if fb['eyes_closed'] == 0 and any(o['eyes_closed'] for o in others):
            reasons.append('eyes open (closed eyes in another frame)')
        elif fb['eyes_closed'] == 0 and not unsure:
            reasons.append('eyes open on all faces')
        elif fb['eyes_closed'] == 0:
            reasons.append('eyes not clear on every face')
        else:
            reasons.append(f"{fb['eyes_closed']} face(s) with eyes possibly closed, still the best frame overall")
        if fb['looking_away'] == 0 and any(o['looking_away'] for o in others):
            reasons.append('looking at the camera (someone looks away in another frame)')
    if not probs[best][1] and any(probs[m][1] for m in members if m != best):
        reasons.append('subject sharp (blurred subject in another frame)')
    if crit['focus'][best] == max(v for v in crit['focus'].values() if v is not None):
        reasons.append('sharpest frame')
    if crit['look'][best] is not None and crit['look'][best] == max(v for v in crit['look'].values() if v is not None):
        reasons.append('best overall look')
    if crit['resolution'][best] == max(crit['resolution'].values()) and len(set(crit['resolution'].values())) > 1:
        reasons.append('highest resolution')
    if not reasons:
        reasons.append('best balance of the criteria')
    if info['all_bad']:
        reasons.append('all frames have a problem')
    if len(members) >= LONG_GROUP:
        reasons.append(f'{len(members)} frames: a long sequence, frames may differ in expression or moment')
    reasons.append('a recommendation: change it with K or "Keep this one"')
    return rows[best]['id'], reasons

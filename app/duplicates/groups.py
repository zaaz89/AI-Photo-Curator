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
                     cancelled: Callable[[], bool] = lambda: False) -> int:
    rows = _assets(conn)
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
                 cancelled: Callable[[], bool] = lambda: False) -> dict:
    rows = _assets(conn)
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

    choices = {r['group_key']: r['sha256'] for r in conn.execute('SELECT group_key, sha256 FROM keeper_choices')}
    with conn:
        conn.execute('DELETE FROM duplicate_groups')
        counts = defaultdict(int)
        for cat, members in groups:
            key = f'{cat}:' + ','.join(sorted(rows[m]['sha256'] for m in members))
            if cat == 'similar_scene':
                keeper, reasons = None, ['different shots of the same scene: keep both']
            else:
                keeper, reasons = _recommend(rows, feats, members, cat, choices.get(key))
            pair_notes = sorted({e for a in members for b in members if a < b
                                 for e in evidence.get(frozenset((a, b)), [])})
            cur = conn.execute('INSERT INTO duplicate_groups (group_key, category, keeper_id, reasons_json) '
                               'VALUES (?, ?, ?, ?)',
                               (key, cat, keeper, json.dumps({'keeper': reasons, 'evidence': pair_notes[:12]},
                                                             ensure_ascii=False)))
            gid = cur.lastrowid
            for m in members:
                conn.execute('INSERT INTO duplicate_members (group_id, asset_id, score) VALUES (?, ?, ?)',
                             (gid, rows[m]['id'], feats[rows[m]['sha256']][1]))
            counts[cat] += 1
    return dict(counts)


def similarity_matrix_block(sigs: np.ndarray, start: int, stop: int) -> np.ndarray:
    x = sigs.astype(np.float32)
    blk = x[start:stop]
    agree = blk @ x.T + (1 - blk) @ (1 - x).T
    return agree / sigs.shape[1]


def _recommend(rows, feats, members, cat, chosen_sha):
    if chosen_sha:
        for m in members:
            if rows[m]['sha256'] == chosen_sha:
                return rows[m]['id'], ['chosen by you']
    if cat == 'exact':
        m = min(members, key=lambda m: (rows[m]['source_id'], rows[m]['rel_path']))
        return rows[m]['id'], ['identical files: any copy is the same; suggested the first source\'s copy']
    sharp = {m: feats[rows[m]['sha256']][1] for m in members}
    res = {m: (rows[m]['width'] or 0) * (rows[m]['height'] or 0) for m in members}
    smax, rmax = max(sharp.values()) or 1, max(res.values()) or 1
    score = {m: 0.7 * sharp[m] / smax + 0.3 * res[m] / rmax for m in members}
    best = max(members, key=lambda m: score[m])
    reasons = [f'sharpest frame ({sharp[best]:.1f} vs median {np.median(list(sharp.values())):.1f})'
               if sharp[best] == smax else f'best balance of sharpness and resolution']
    if res[best] == rmax and len(set(res.values())) > 1:
        reasons.append('highest resolution')
    if len(members) >= LONG_GROUP:
        reasons.append(f'{len(members)} frames: a long sequence, frames may differ in expression or moment')
    reasons.append('a recommendation only: expressions and moments are not judged yet')
    return rows[best]['id'], reasons

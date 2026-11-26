"""Per-day pipeline bookkeeping and the live event stream (M13).

The Sorting page follows the analysis through ordered events instead of guessing from reloads:

  read         a photo was indexed (it can fly in)
  scored       its results are in and it stays in the album
  removed      it leaves the album (reason: screenshot | leftOut | movement_blur | subject_blurry | whole_blurry)
  stacked      another frame of a moment (keeper_id: the moment's best frame)
  settled_day  every photo of that day has its final place (asset_id is null)

An asset gets a new event only when its place changes, so the stream is short and the newest event of an asset
is its current place. Events live in `analysis_events` (seq never repeats) and go away with the album database
("Finish album"); `prune` empties them explicitly. `analysis_days` records the settled days and a signature of
their photos and corrected times, so a stopped analysis resumes at the first unsettled day and a clock change
rebuilds only the days it moved.
"""
from __future__ import annotations

import hashlib
from collections import defaultdict

from app.collections import now_iso

KINDS = ('read', 'scored', 'removed', 'stacked', 'settled_day')
BLUR_REASON = {'movement': 'movement_blur', 'subject': 'subject_blurry', 'whole': 'whole_blurry'}
PAGE = 500
MAX_PAGE = 2000


# ---- days ----------------------------------------------------------------------------------------------------

def day_plan(conn) -> list:
    """[(day, [asset dict])] in chronological order ("unknown" last); assets in time order.
    Asset dict: id, sha256, kind, t."""
    from app.timeline.event_detector import _rows
    info = {r['id']: r for r in conn.execute(
        "SELECT id, sha256, kind FROM assets WHERE status = 'present'")}
    by_day = defaultdict(list)
    for r in _rows(conn):
        a = info.get(r['id'])
        if a is None:
            continue
        by_day[r['day']].append({'id': r['id'], 'sha256': a['sha256'], 'kind': a['kind'], 't': r['t']})
    days = sorted(d for d in by_day if d != 'unknown')
    if 'unknown' in by_day:
        days.append('unknown')
    return [(d, by_day[d]) for d in days]


def signature(assets: list) -> str:
    h = hashlib.sha1()
    for a in sorted(assets, key=lambda a: a['id']):
        h.update(f"{a['id']}:{a['sha256']}:{round(a['t'] or 0.0, 3)};".encode())
    return h.hexdigest()


def settled_days(conn) -> dict:
    """day -> signature of the days settled so far."""
    return {r['day']: r['signature'] for r in conn.execute('SELECT day, signature FROM analysis_days')}


def mark_settled(conn, day: str, sig: str) -> None:
    with conn:
        conn.execute('INSERT INTO analysis_days (day, signature, settled_at) VALUES (?, ?, ?) ON CONFLICT(day) '
                     'DO UPDATE SET signature = excluded.signature, settled_at = excluded.settled_at',
                     (day, sig, now_iso()))


def forget_days(conn, days) -> None:
    with conn:
        conn.executemany('DELETE FROM analysis_days WHERE day = ?', [(d,) for d in days])


# ---- where each photo ends up (same rule as the app's sortVerdict / the export) -----------------------------

def places(conn, ids) -> dict:
    """asset id -> (kind, reason, keeper_id) for the given assets, from the stored results."""
    from app.quality.scoring import focus_tiers
    from app.quality.screenshots import screenshot_ids
    ids = list(ids)
    if not ids:
        return {}
    want = set(ids)
    assets = {r['id']: r for r in conn.execute("SELECT id, sha256, kind FROM assets WHERE status = 'present'")
              if r['id'] in want}
    marks = {r['sha256']: r for r in conn.execute('SELECT sha256, favorite, rejected, keep FROM marks')}
    tiers = focus_tiers(conn)
    shots = screenshot_ids(conn)
    extra = {}
    for r in conn.execute("SELECT m.asset_id, g.keeper_id FROM duplicate_members m "
                          "JOIN duplicate_groups g ON g.id = m.group_id WHERE g.category IN ('exact', 'near')"):
        if r['keeper_id'] is not None and r['asset_id'] != r['keeper_id']:
            extra[r['asset_id']] = r['keeper_id']
    out = {}
    for aid in ids:
        a = assets.get(aid)
        if a is None:
            continue
        m = marks.get(a['sha256'])
        fav, rej, keep = (bool(m['favorite']), bool(m['rejected']), bool(m['keep'])) if m else (False, False, False)
        t = tiers.get(aid) or {}
        blurry = a['kind'] == 'image' and t.get('tier') == 'blurry'
        shot = aid in shots
        is_extra = aid in extra
        in_album = not rej and (fav or ((not shot or keep) and not blurry and (not is_extra or keep)))
        if in_album:
            out[aid] = ('scored', None, None)
        elif not rej and is_extra and not blurry:
            out[aid] = ('stacked', None, extra[aid])
        elif rej:
            out[aid] = ('removed', 'leftOut', None)
        elif shot and not keep:
            out[aid] = ('removed', 'screenshot', None)
        else:
            out[aid] = ('removed', BLUR_REASON.get(t.get('blur_reason') or '', 'whole_blurry'), None)
    return out


# ---- the stream -----------------------------------------------------------------------------------------------

def _last(conn) -> dict:
    """asset id -> (kind, reason, keeper_id) of its newest event (read included)."""
    out = {}
    for r in conn.execute('SELECT asset_id, kind, reason, keeper_id FROM analysis_events '
                          'WHERE asset_id IS NOT NULL ORDER BY seq'):
        out[r['asset_id']] = (r['kind'], r['reason'], r['keeper_id'])
    return out


def _insert(conn, rows) -> int:
    if not rows:
        return 0
    now = now_iso()
    with conn:
        conn.executemany('INSERT INTO analysis_events (asset_id, kind, reason, keeper_id, day, created_at) '
                         'VALUES (?, ?, ?, ?, ?, ?)', [(*r, now) for r in rows])
    return len(rows)


def emit_read(conn, plan) -> int:
    """A `read` event for every photo that has no event yet, in time order."""
    have = {r[0] for r in conn.execute('SELECT DISTINCT asset_id FROM analysis_events WHERE asset_id IS NOT NULL')}
    rows = []
    for day, assets in plan:
        rows += [(a['id'], 'read', None, None, day) for a in assets if a['id'] not in have]
    return _insert(conn, rows)


def emit_places(conn, plan, days=None, settled: bool = False) -> int:
    """For the given days (default: all of `plan`), an event for every photo whose place changed since its
    newest event, in time order; with `settled` also one `settled_day` per day."""
    last = _last(conn)
    chosen = [(d, a) for d, a in plan if days is None or d in days]
    now = places(conn, [x['id'] for _, assets in chosen for x in assets])
    rows = []
    for day, assets in chosen:
        for a in assets:
            p = now.get(a['id'])
            if p is not None and last.get(a['id']) != p:
                rows.append((a['id'], p[0], p[1], p[2], day))
        if settled:
            rows.append((None, 'settled_day', None, None, day))
    return _insert(conn, rows)


def events_since(conn, since: int = 0, limit: int = PAGE) -> dict:
    """Events with seq > since, oldest first, at most `limit`. `next` is the cursor for the next call."""
    limit = max(1, min(int(limit), MAX_PAGE))
    rows = conn.execute('SELECT seq, asset_id, kind, reason, keeper_id, day FROM analysis_events WHERE seq > ? '
                        'ORDER BY seq LIMIT ?', (int(since), limit + 1)).fetchall()
    more = len(rows) > limit
    rows = rows[:limit]
    latest = conn.execute('SELECT COALESCE(MAX(seq), 0) FROM analysis_events').fetchone()[0]
    events = []
    for r in rows:
        e = {'seq': r['seq'], 'asset_id': r['asset_id'], 'kind': r['kind'], 'day': r['day']}
        if r['reason'] is not None:
            e['reason'] = r['reason']
        if r['keeper_id'] is not None:
            e['keeper_id'] = r['keeper_id']
        events.append(e)
    return {'events': events, 'next': rows[-1]['seq'] if rows else int(since), 'more': more, 'latest': latest}


def prune(conn) -> int:
    with conn:
        return conn.execute('DELETE FROM analysis_events').rowcount


# ---- rebuilding days after an owner change --------------------------------------------------------------------

def rebuild_changed_days(conn) -> dict:
    """After a clock change: rebuild the moments of the settled days whose photos or corrected times changed
    (and of new days the change created), leave every other day alone. Albums analysed before M13 have no
    settled days; they get the whole-album rebuild as before."""
    from app.duplicates.groups import build_groups, refresh_keepers
    done = settled_days(conn)
    if not done:
        return {'whole_album': build_groups(conn)}
    from app.timeline.event_detector import asset_days
    plan = day_plan(conn)
    day_of = asset_days(conn)
    current = {d: signature(a) for d, a in plan}
    changed = [d for d, s in current.items() if done.get(d) != s]
    for d in changed:
        build_groups(conn, day=d, day_of=day_of)
        mark_settled(conn, d, current[d])
    gone = [d for d in done if d not in current]
    forget_days(conn, gone)
    refresh_keepers(conn)
    emit_places(conn, plan, days=set(settled_days(conn)))
    if changed:
        _insert(conn, [(None, 'settled_day', None, None, d) for d in changed])
    return {'rebuilt_days': changed, 'gone_days': gone}


def after_owner_change(conn) -> None:
    """A keeper choice or a mark changed places: keepers again (no photo is compared), then events."""
    from app.duplicates.groups import refresh_keepers
    refresh_keepers(conn)
    emit_places(conn, day_plan(conn), days=set(settled_days(conn)))

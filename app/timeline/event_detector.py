"""Group the timeline into events (brief section 7).

Within one local day, a new event starts when
  - more than 2 hours pass between two photos, or
  - more than 30 minutes pass and the place moved more than 2 km, or
  - the place jumps more than 15 km (a drive), whatever the time.
Photos from all sources are merged first, so both people's photos of the same
afternoon land in one event. Clock corrections are applied.

Names are built only from facts: the most common place of the event (from
GPS) and the part of the day, e.g. "Florence, afternoon". The owner can
rename, merge and split. A day the owner edited is locked: re-analysis keeps
its events and only adds new photos to the nearest event by time.
"""
from __future__ import annotations

import math
from collections import Counter
from datetime import datetime, timedelta, timezone

GAP_LONG_S = 2 * 3600
GAP_MOVE_S = 30 * 60
MOVE_KM = 2.0
JUMP_KM = 15.0


def _km(a, b):
    if not a or not b:
        return 0.0
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(h))


def _rows(conn):
    rows = conn.execute(
        'SELECT a.id, c.local_time, c.utc_time, c.confidence, '
        'c.sort_key + COALESCE(cc.applied_s, 0) AS t, COALESCE(cc.applied_s, 0) AS shift, '
        'a.gps_lat, a.gps_lon, p.name AS place, p.label, p.precision '
        'FROM assets a LEFT JOIN capture_time c ON c.asset_id = a.id '
        "LEFT JOIN clocks k ON k.source_id = a.source_id AND k.make = COALESCE(a.make, '') "
        "  AND k.model = COALESCE(a.model, '') "
        'LEFT JOIN clock_corrections cc ON cc.clock_id = k.id '
        'LEFT JOIN places p ON p.asset_id = a.id '
        "WHERE a.status = 'present' ORDER BY t, a.id").fetchall()
    out = []
    for r in rows:
        local = r['local_time'] or (r['utc_time'] or '').replace('Z', '')
        if local and r['confidence'] != 'unknown':
            dt = datetime.fromisoformat(local) + timedelta(seconds=r['shift'] or 0)
            day, hour = dt.date().isoformat(), dt.hour
        else:
            day, hour = 'unknown', None
        out.append({'id': r['id'], 't': r['t'] or 0.0, 'day': day, 'hour': hour,
                    'gps': (r['gps_lat'], r['gps_lon']) if r['gps_lat'] is not None else None,
                    'place': r['place'], 'label': r['label'], 'precision': r['precision']})
    return out


def part_of_day(hour):
    if hour is None:
        return 'time unknown'
    if 5 <= hour < 12:
        return 'morning'
    if 12 <= hour < 17:
        return 'afternoon'
    if 17 <= hour < 21:
        return 'evening'
    return 'night'


def auto_name(members) -> tuple[str, str | None]:
    """(name, place_label) from facts only."""
    places = Counter(m['place'] for m in members if m['place'] and m['precision'] in ('in', 'near'))
    place_label = None
    if places:
        name = places.most_common(1)[0][0]
        precs = Counter(m['precision'] for m in members if m['place'] == name)
        place_label = name if precs['in'] >= precs['near'] else f'near {name}'
    else:
        regions = Counter(m['label'] for m in members if m['label'])
        if regions:
            place_label = regions.most_common(1)[0][0]
    hours = [m['hour'] for m in members if m['hour'] is not None]
    part = part_of_day(sorted(hours)[len(hours) // 2] if hours else None)
    if members and members[0]['day'] == 'unknown':
        return 'Photos without a capture date', place_label
    name = f'{place_label}, {part}' if place_label else part.capitalize()
    return name, place_label


def split_day(members):
    groups, cur = [], []
    for m in members:
        if cur:
            prev = cur[-1]
            gap = m['t'] - prev['t']
            km = _km(prev['gps'], m['gps']) if prev['gps'] and m['gps'] else 0.0
            if gap > GAP_LONG_S or (gap > GAP_MOVE_S and km > MOVE_KM) or km > JUMP_KM:
                groups.append(cur)
                cur = []
        cur.append(m)
    if cur:
        groups.append(cur)
    return groups


def detect_events(conn) -> dict:
    rows = _rows(conn)
    by_day = {}
    for r in rows:
        by_day.setdefault(r['day'], []).append(r)
    locked_days = {r['day'] for r in conn.execute('SELECT DISTINCT day FROM events WHERE locked = 1')}
    created = kept = added = 0
    with conn:
        conn.execute('DELETE FROM events WHERE locked = 0')
        for day, members in sorted(by_day.items()):
            if day in locked_days:
                evs = conn.execute('SELECT id, start_key, end_key FROM events WHERE day = ? ORDER BY start_key',
                                   (day,)).fetchall()
                have = {r[0] for r in conn.execute(
                    'SELECT m.asset_id FROM event_members m JOIN events e ON e.id = m.event_id WHERE e.day = ?',
                    (day,))}
                for m in members:
                    if m['id'] in have:
                        continue
                    best = min(evs, key=lambda e: 0 if e['start_key'] <= m['t'] <= e['end_key']
                               else min(abs(m['t'] - e['start_key']), abs(m['t'] - e['end_key'])))
                    conn.execute('INSERT OR REPLACE INTO event_members (event_id, asset_id) VALUES (?, ?)',
                                 (best['id'], m['id']))
                    added += 1
                _refresh_bounds(conn, day)
                kept += len(evs)
                continue
            for g in ([members] if day == 'unknown' else split_day(members)):
                name, place = auto_name(g)
                cur = conn.execute('INSERT INTO events (day, start_key, end_key, name, name_source, place_label) '
                                   "VALUES (?, ?, ?, ?, 'auto', ?)", (day, g[0]['t'], g[-1]['t'], name, place))
                conn.executemany('INSERT OR REPLACE INTO event_members (event_id, asset_id) VALUES (?, ?)',
                                 [(cur.lastrowid, m['id']) for m in g])
                created += 1
    return {'created': created, 'kept_locked': kept, 'added_to_locked': added}


def _refresh_bounds(conn, day):
    # Events left without photos (all moved elsewhere) go first, so the bounds below are never NULL.
    conn.execute('DELETE FROM events WHERE day = ? AND id NOT IN (SELECT DISTINCT event_id FROM event_members)', (day,))
    conn.execute(
        'UPDATE events SET start_key = (SELECT MIN(c.sort_key) FROM event_members m JOIN capture_time c '
        '  ON c.asset_id = m.asset_id WHERE m.event_id = events.id), '
        'end_key = (SELECT MAX(c.sort_key) FROM event_members m JOIN capture_time c '
        '  ON c.asset_id = m.asset_id WHERE m.event_id = events.id) WHERE day = ?', (day,))


# --- owner's edits --------------------------------------------------------- #

def _lock(conn, day):
    conn.execute('UPDATE events SET locked = 1 WHERE day = ?', (day,))


def rename_event(conn, event_id: int, name: str) -> None:
    name = (name or '').strip()
    if not name:
        raise ValueError('name is required')
    ev = conn.execute('SELECT day FROM events WHERE id = ?', (event_id,)).fetchone()
    if not ev:
        raise ValueError('unknown event')
    with conn:
        conn.execute("UPDATE events SET name = ?, name_source = 'user' WHERE id = ?", (name[:120], event_id))
        _lock(conn, ev['day'])


def merge_with_previous(conn, event_id: int) -> int:
    ev = conn.execute('SELECT * FROM events WHERE id = ?', (event_id,)).fetchone()
    if not ev:
        raise ValueError('unknown event')
    prev = conn.execute('SELECT * FROM events WHERE day = ? AND start_key < ? ORDER BY start_key DESC LIMIT 1',
                        (ev['day'], ev['start_key'])).fetchone()
    if not prev:
        raise ValueError('this is the first event of the day')
    with conn:
        conn.execute('UPDATE event_members SET event_id = ? WHERE event_id = ?', (prev['id'], event_id))
        conn.execute('DELETE FROM events WHERE id = ?', (event_id,))
        _lock(conn, ev['day'])
        _refresh_bounds(conn, ev['day'])
    return prev['id']


def split_at(conn, asset_id: int) -> int:
    """Start a new event at this photo; it and all later photos of its event move."""
    row = conn.execute('SELECT m.event_id, e.day, e.name_source FROM event_members m JOIN events e ON e.id = m.event_id '
                       'WHERE m.asset_id = ?', (asset_id,)).fetchone()
    if not row:
        raise ValueError('photo is not in an event')
    t = conn.execute('SELECT sort_key FROM capture_time WHERE asset_id = ?', (asset_id,)).fetchone()[0]
    rest = [r[0] for r in conn.execute(
        'SELECT m.asset_id FROM event_members m JOIN capture_time c ON c.asset_id = m.asset_id '
        'WHERE m.event_id = ? AND (c.sort_key > ? OR (c.sort_key = ? AND m.asset_id >= ?))',
        (row['event_id'], t, t, asset_id))]
    total = conn.execute('SELECT COUNT(*) FROM event_members WHERE event_id = ?', (row['event_id'],)).fetchone()[0]
    if len(rest) == total:
        raise ValueError('this photo already starts its event')
    members = [m for m in _rows(conn) if m['id'] in set(rest)]
    name, place = auto_name(members)
    with conn:
        cur = conn.execute('INSERT INTO events (day, start_key, end_key, name, name_source, place_label) '
                           "VALUES (?, ?, ?, ?, 'auto', ?)", (row['day'], t, t, name, place))
        conn.executemany('UPDATE event_members SET event_id = ? WHERE asset_id = ?',
                         [(cur.lastrowid, a) for a in rest])
        _lock(conn, row['day'])
        _refresh_bounds(conn, row['day'])
    return cur.lastrowid


def reset_day(conn, day: str) -> None:
    """Undo the owner's edits for a day: back to automatic events."""
    with conn:
        conn.execute('DELETE FROM events WHERE day = ?', (day,))
    detect_events(conn)


def move_to_event(conn, asset_ids: list[int], event_id: int | None, new_name: str | None = None) -> int:
    """Move photos into an existing event, or (event_id None) into a new event named new_name.
    Locks every affected day so re-analysis keeps the owner's arrangement."""
    if not asset_ids:
        raise ValueError('no photos selected')
    days = {r[0] for r in conn.execute(
        f"SELECT DISTINCT e.day FROM event_members m JOIN events e ON e.id = m.event_id "
        f"WHERE m.asset_id IN ({','.join('?' * len(asset_ids))})", asset_ids)}
    with conn:
        if event_id is None:
            members = [m for m in _rows(conn) if m['id'] in set(asset_ids)]
            if not members:
                raise ValueError('unknown photos')
            name, place = auto_name(members)
            cur = conn.execute('INSERT INTO events (day, start_key, end_key, name, name_source, place_label, locked) '
                               'VALUES (?, ?, ?, ?, ?, ?, 1)',
                               (members[0]['day'], members[0]['t'], members[-1]['t'], (new_name or name)[:120],
                                'user' if new_name else 'auto', place))
            event_id = cur.lastrowid
            days.add(members[0]['day'])
        else:
            ev = conn.execute('SELECT day FROM events WHERE id = ?', (event_id,)).fetchone()
            if not ev:
                raise ValueError('unknown event')
            days.add(ev['day'])
        conn.executemany('INSERT OR REPLACE INTO event_members (event_id, asset_id) VALUES (?, ?)',
                         [(event_id, a) for a in asset_ids])
        for d in days:
            _lock(conn, d)
            _refresh_bounds(conn, d)
    return event_id

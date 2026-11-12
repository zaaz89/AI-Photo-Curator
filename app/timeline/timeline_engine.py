"""Unified chronological view across all sources of a collection.

Accepted or manual clock corrections (app/timeline/clock_sync.py) shift the
order and the displayed time. The original resolved time stays available as
local_time / utc_time; the corrected values are separate fields.
"""
from __future__ import annotations

import json
import os
import sqlite3
from collections import Counter
from datetime import datetime, timedelta, timezone

from app.ai.vision_analyzer import tidy_description


def _shift_iso(value, seconds, utc=False):
    if not value or not seconds:
        return value
    dt = datetime.fromisoformat(value.replace('Z', '+00:00') if utc else value)
    out = (dt + timedelta(seconds=seconds)).isoformat()
    return out.replace('+00:00', 'Z') if utc else out


def timeline(conn: sqlite3.Connection) -> dict:
    rows = conn.execute(
        'SELECT a.id, a.rel_path, a.filename, a.kind, a.ext, a.make, a.model, a.width, a.height, '
        'a.gps_lat, a.gps_lon, a.sha256, s.id AS source_id, s.owner, s.label, s.path AS source_path, '
        'c.local_time, c.utc_time, c.offset_minutes, c.rule, c.confidence, c.notes_json, c.sort_key, '
        'k.id AS clock_id, COALESCE(cc.applied_s, 0) AS applied_s, cc.status AS clock_status, '
        'p.label AS place_label, p.precision AS place_precision, p.distance_km, p.region, p.country, '
        'em.event_id '
        'FROM assets a JOIN sources s ON s.id = a.source_id '
        'LEFT JOIN places p ON p.asset_id = a.id LEFT JOIN event_members em ON em.asset_id = a.id '
        'LEFT JOIN capture_time c ON c.asset_id = a.id '
        "LEFT JOIN clocks k ON k.source_id = a.source_id AND k.make = COALESCE(a.make, '') "
        "  AND k.model = COALESCE(a.model, '') "
        'LEFT JOIN clock_corrections cc ON cc.clock_id = k.id '
        "WHERE a.status = 'present' "
        'ORDER BY c.sort_key IS NULL, c.sort_key + COALESCE(cc.applied_s, 0), s.id, a.rel_path').fetchall()
    rel = {}
    for r in conn.execute('SELECT kind, asset_a, asset_b FROM relationships'):
        rel.setdefault(r['asset_a'], []).append({'kind': r['kind'], 'with': r['asset_b']})
        rel.setdefault(r['asset_b'], []).append({'kind': r['kind'], 'with': r['asset_a']})
    dup = {}
    for r in conn.execute('SELECT m.asset_id, g.id, g.category, g.keeper_id FROM duplicate_members m '
                          'JOIN duplicate_groups g ON g.id = m.group_id'):
        if r['category'] != 'similar_scene' or r['asset_id'] not in dup:
            dup[r['asset_id']] = {'group': r['id'], 'category': r['category'],
                                  'keeper': r['keeper_id'] == r['asset_id'] if r['keeper_id'] else None}
    sha_count = Counter(r['sha256'] for r in rows if r['sha256'])
    ai = {}
    for r in conn.execute('SELECT sha256, model, description, tags_json, people, text_visible FROM ai_annotations '
                          'WHERE error IS NULL ORDER BY created_at'):
        ai[r['sha256']] = {'model': r['model'], 'description': tidy_description(r['description']),
                           'tags': json.loads(r['tags_json'] or '[]'), 'people': r['people'],
                           'text_visible': r['text_visible']}

    items = []
    for r in rows:
        device = ' '.join(x for x in (r['make'], r['model']) if x)
        if r['make'] and r['model'] and r['model'].upper().startswith(r['make'].upper()):
            device = r['model']
        shift = r['applied_s'] or 0
        items.append({
            'id': r['id'],
            'path': os.path.join(r['source_path'], r['rel_path']),
            'rel_path': r['rel_path'],
            'filename': r['filename'],
            'kind': r['kind'],
            'ext': r['ext'],
            'source_id': r['source_id'],
            'owner': r['owner'],
            'device': device or 'unknown device',
            'clock_id': r['clock_id'],
            'width': r['width'], 'height': r['height'],
            'gps': [r['gps_lat'], r['gps_lon']] if r['gps_lat'] is not None else None,
            'local_time': r['local_time'],
            'utc_time': r['utc_time'],
            'clock_correction_s': shift,
            'corrected_local_time': _shift_iso(r['local_time'], shift),
            'corrected_utc_time': _shift_iso(r['utc_time'], shift, utc=True),
            'offset_minutes': r['offset_minutes'],
            'rule': r['rule'],
            'confidence': r['confidence'] or 'unknown',
            'notes': json.loads(r['notes_json'] or '[]'),
            'related': rel.get(r['id'], []),
            'exact_copies': sha_count[r['sha256']] - 1 if r['sha256'] else 0,
            'duplicate': dup.get(r['id']),
            'ai': ai.get(r['sha256']),
            'place': ({'label': r['place_label'], 'precision': r['place_precision'],
                       'distance_km': r['distance_km'], 'region': r['region'], 'country': r['country']}
                      if r['place_label'] else None),
            'event_id': r['event_id'],
        })
    summary = {
        'assets': len(items),
        'by_confidence': dict(Counter(i['confidence'] for i in items)),
        'by_source': dict(Counter(i['owner'] for i in items)),
        'by_device': dict(Counter(i['device'] for i in items)),
        'relationships': dict(Counter(r['kind'] for r in conn.execute('SELECT kind FROM relationships'))),
        'duplicate_groups': dict(Counter(r['category'] for r in conn.execute('SELECT category FROM duplicate_groups'))),
        'described': sum(1 for i in items if i['ai']),
        'corrected_clocks': conn.execute("SELECT COUNT(*) FROM clock_corrections WHERE applied_s != 0").fetchone()[0],
    }
    from app.quality.scoring import focus_tiers
    tiers = focus_tiers(conn)
    marks = {r['sha256']: r for r in conn.execute('SELECT sha256, wallpaper, excluded FROM marks')}
    sha_of = {r['id']: r['sha256'] for r in rows}
    for i in items:
        i['focus'] = tiers.get(i['id'])
        m = marks.get(sha_of.get(i['id']))
        i['wallpaper'] = bool(m['wallpaper']) if m else False
        i['excluded'] = bool(m['excluded']) if m else False
    summary['focus'] = dict(Counter(v['tier'] for v in tiers.values()))
    counts = Counter(i['event_id'] for i in items if i['event_id'])
    events = [{'id': e['id'], 'day': e['day'], 'name': e['name'], 'name_source': e['name_source'],
               'place_label': e['place_label'], 'locked': bool(e['locked']), 'count': counts.get(e['id'], 0)}
              for e in conn.execute('SELECT * FROM events ORDER BY day, start_key')]
    summary['events'] = len(events)
    summary['with_place'] = sum(1 for i in items if i['place'])
    return {'summary': summary, 'items': items, 'events': events}


def duplicate_groups(conn: sqlite3.Connection) -> list:
    groups = []
    for g in conn.execute('SELECT * FROM duplicate_groups ORDER BY id'):
        members = conn.execute(
            "SELECT a.id, a.filename, a.rel_path, a.width, a.height, a.size, s.owner, s.path || '/' || a.rel_path AS path, "
            "a.make, a.model, m.score AS sharpness, c.local_time FROM duplicate_members m "
            'JOIN assets a ON a.id = m.asset_id JOIN sources s ON s.id = a.source_id '
            'LEFT JOIN capture_time c ON c.asset_id = a.id WHERE m.group_id = ? ORDER BY c.sort_key, a.id',
            (g['id'],)).fetchall()
        groups.append({'id': g['id'], 'category': g['category'], 'keeper_id': g['keeper_id'],
                       'reasons': json.loads(g['reasons_json']), 'members': [dict(m) for m in members]})
    order = {'exact': 0, 'near': 1, 'similar_scene': 2}
    return sorted(groups, key=lambda g: (order.get(g['category'], 9), g['id']))

"""Unified chronological view across all sources of a collection."""
from __future__ import annotations

import json
import os
import sqlite3
from collections import Counter


def timeline(conn: sqlite3.Connection) -> dict:
    rows = conn.execute(
        'SELECT a.id, a.rel_path, a.filename, a.kind, a.ext, a.make, a.model, a.width, a.height, '
        'a.gps_lat, a.gps_lon, a.sha256, s.id AS source_id, s.owner, s.label, s.path AS source_path, '
        'c.local_time, c.utc_time, c.offset_minutes, c.rule, c.confidence, c.notes_json, c.sort_key '
        'FROM assets a JOIN sources s ON s.id = a.source_id '
        'LEFT JOIN capture_time c ON c.asset_id = a.id '
        "WHERE a.status = 'present' "
        'ORDER BY c.sort_key IS NULL, c.sort_key, s.id, a.rel_path').fetchall()
    rel = {}
    for r in conn.execute('SELECT kind, asset_a, asset_b FROM relationships'):
        rel.setdefault(r['asset_a'], []).append({'kind': r['kind'], 'with': r['asset_b']})
        rel.setdefault(r['asset_b'], []).append({'kind': r['kind'], 'with': r['asset_a']})
    sha_count = Counter(r['sha256'] for r in rows if r['sha256'])

    items = []
    for r in rows:
        device = ' '.join(x for x in (r['make'], r['model']) if x)
        if r['make'] and r['model'] and r['model'].upper().startswith(r['make'].upper()):
            device = r['model']
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
            'width': r['width'], 'height': r['height'],
            'gps': [r['gps_lat'], r['gps_lon']] if r['gps_lat'] is not None else None,
            'local_time': r['local_time'],
            'utc_time': r['utc_time'],
            'offset_minutes': r['offset_minutes'],
            'rule': r['rule'],
            'confidence': r['confidence'] or 'unknown',
            'notes': json.loads(r['notes_json'] or '[]'),
            'related': rel.get(r['id'], []),
            'exact_copies': sha_count[r['sha256']] - 1 if r['sha256'] else 0,
        })
    summary = {
        'assets': len(items),
        'by_confidence': dict(Counter(i['confidence'] for i in items)),
        'by_source': dict(Counter(i['owner'] for i in items)),
        'by_device': dict(Counter(i['device'] for i in items)),
        'relationships': dict(Counter(r['kind'] for r in conn.execute('SELECT kind FROM relationships'))),
    }
    return {'summary': summary, 'items': items}

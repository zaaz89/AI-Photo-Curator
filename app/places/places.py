"""Attach a place to every photo that has GPS (offline, see geocoder.py)."""
from __future__ import annotations

from app.places.geocoder import GeoUnavailable, get_index

SOURCE = 'gps + geonames cities500'


def assign_places(conn) -> dict:
    try:
        idx = get_index()
    except GeoUnavailable as e:
        return {'skipped': str(e)}
    rows = conn.execute("SELECT id, gps_lat, gps_lon FROM assets WHERE status = 'present' "
                        'AND gps_lat IS NOT NULL AND gps_lon IS NOT NULL').fetchall()
    counts = {'in': 0, 'near': 0, 'region': 0}
    with conn:
        conn.execute('DELETE FROM places')
        for r in rows:
            if abs(r['gps_lat']) < 1e-6 and abs(r['gps_lon']) < 1e-6:
                continue                                   # 0,0 = missing GPS written as zeros
            p = idx.reverse(r['gps_lat'], r['gps_lon'])
            conn.execute('INSERT INTO places (asset_id, name, label, precision, distance_km, region, country, '
                         'aliases, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                         (r['id'], p['name'], p['label'], p['precision'], p['distance_km'], p['region'],
                          p['country'], p.get('aliases', ''), SOURCE))
            counts[p['precision']] += 1
    return counts

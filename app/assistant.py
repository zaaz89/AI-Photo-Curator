"""The album assistant (M8 phase 2): suggestions for the New Album wizard and the Overview.

Suggestions only read a sample of each folder (ExifTool, nothing is written) and the offline
GeoNames index. The overview summarises what still needs the owner's decision.
"""
from __future__ import annotations

import json
import os
import subprocess
from collections import Counter

from app import settings
from app.importers.local_importer import walk_source
from app.metadata.exif_reader import exiftool_path

SAMPLE = 40
GENERIC_FOLDERS = {'dcim', 'camera', 'photos', 'pictures', 'images', 'export', 'exports', 'img', 'download',
                   'downloads', 'desktop', 'new folder', 'untitled folder', 'fotografije', 'slike', 'nova mapa'}
SECONDS_PER_DESCRIPTION = 8          # at the default 30 % GPU limit (measured on test-10)


def device_name(make, model) -> str:
    """Same naming as the timeline: "Apple iPhone 15", "SONY ILCE-7M4"."""
    make, model = (make or '').strip(), (model or '').strip()
    if make and model and model.upper().startswith(make.upper()):
        return model
    return ' '.join(x for x in (make, model) if x)


def _read_sample(paths: list[str]) -> list[dict]:
    exe = exiftool_path()
    if not exe or not paths:
        return []
    args = [exe, '-json', '-n', '-charset', 'filename=utf8', '-q', '-q', '-Make', '-Model', '-Artist',
            '-OwnerName', '-CameraOwnerName', '-DateTimeOriginal', '-CreateDate', '-GPSLatitude', '-GPSLongitude',
            '-@', '-']
    proc = subprocess.run(args, input='\n'.join(paths), capture_output=True, text=True, timeout=120)
    try:
        return json.loads(proc.stdout or '[]')
    except json.JSONDecodeError:
        return []


def _clean_folder_name(path: str) -> str:
    name = os.path.basename(os.path.normpath(path)).strip()
    return '' if name.lower() in GENERIC_FOLDERS or name.isdigit() else name


def suggest(paths: list[str]) -> dict:
    remembered = settings.load().get('device_owners') or {}
    folders, rejected, seen, places, days = [], [], set(), [], []
    for raw in paths:
        path = os.path.realpath(str(raw))
        if path in seen:
            continue
        seen.add(path)
        if not os.path.exists(path):
            rejected.append({'path': raw, 'problem': 'not found'})
            continue
        if not os.path.isdir(path):
            rejected.append({'path': raw, 'problem': 'not a folder'})
            continue
        files = [f for f, _ in walk_source(path)]
        if not files:
            rejected.append({'path': raw, 'problem': 'no photos or videos'})
            continue
        step = max(1, len(files) // SAMPLE)
        rows = _read_sample(files[::step][:SAMPLE])
        devices = Counter(d for d in (device_name(r.get('Make'), r.get('Model')) for r in rows) if d)
        artists = Counter(str(v).strip() for r in rows for k in ('Artist', 'OwnerName', 'CameraOwnerName')
                          if (v := r.get(k)) and str(v).strip())
        dates = sorted(str(r.get('DateTimeOriginal') or r.get('CreateDate'))[:10].replace(':', '-')
                       for r in rows if r.get('DateTimeOriginal') or r.get('CreateDate'))
        dates = [d for d in dates if d[:4].isdigit() and d > '1990']
        days += dates
        for r in rows:
            lat, lon = r.get('GPSLatitude'), r.get('GPSLongitude')
            if isinstance(lat, (int, float)) and isinstance(lon, (int, float)) and (lat or lon):
                places.append((lat, lon))
        owner, source = '', ''
        for dev, _ in devices.most_common():
            if remembered.get(dev):
                owner, source = remembered[dev], 'remembered'
                break
        if not owner and artists:
            owner, source = artists.most_common(1)[0][0], 'exif'
        if not owner and (name := _clean_folder_name(path)):
            owner, source = name, 'folder'
        folders.append({'path': path, 'count': len(files), 'owner': owner, 'owner_from': source or None,
                        'devices': [{'name': d, 'count': n} for d, n in devices.most_common(4)],
                        'start': dates[0] if dates else None, 'end': dates[-1] if dates else None})
    return {'folders': folders, 'rejected': rejected, 'album': _album(places, sorted(days))}


def _album(places, days) -> dict:
    out = {'place': None, 'region': None, 'country': None,
           'start': days[0] if days else None, 'end': days[-1] if days else None}
    if not places:
        return out
    try:
        from app.places.geocoder import GeoUnavailable, get_index
        idx = get_index()
    except Exception:
        return out
    try:
        found = [idx.reverse(lat, lon) for lat, lon in places[:200]]
    except GeoUnavailable:
        return out
    cities = Counter(f['name'] for f in found if f.get('name'))
    regions = Counter(f['region'] for f in found if f.get('region'))
    countries = Counter(f['country'] for f in found if f.get('country'))
    region = regions.most_common(1)[0][0] if regions else None
    # One city: its name; several: the region (e.g. "Tuscany"); otherwise the country.
    place = (cities.most_common(1)[0][0] if len(cities) == 1 else region) or (cities.most_common(1)[0][0] if cities else None)
    out.update(place=place, region=region, country=countries.most_common(1)[0][0] if countries else None)
    return out


def overview(conn, job: dict | None = None) -> dict:
    from app.quality.scoring import focus_tiers
    from app.timeline.clock_sync import list_clocks
    present = "a.status = 'present'"
    photos = conn.execute(f"SELECT COUNT(*) FROM assets a WHERE {present}").fetchone()[0]
    images = conn.execute(f"SELECT COUNT(*) FROM assets a WHERE {present} AND kind = 'image'").fetchone()[0]
    videos = photos - images
    marks = {r['sha256']: r for r in conn.execute('SELECT sha256, favorite, rejected FROM marks')}
    ids = conn.execute(f"SELECT id, sha256 FROM assets a WHERE {present}").fetchall()
    rejected = {r['id'] for r in ids if marks.get(r['sha256']) and marks[r['sha256']]['rejected']}
    favourite = {r['id'] for r in ids if marks.get(r['sha256']) and marks[r['sha256']]['favorite']}

    clocks = list_clocks(conn)
    pending = sum(1 for c in clocks if c.get('suggested_s') is not None
                  and c.get('status') not in ('accepted', 'manual', 'rejected', 'reference'))
    applied = sum(1 for c in clocks if c.get('applied_s'))

    total = decided = chosen = 0
    for g in conn.execute("SELECT reasons_json FROM duplicate_groups WHERE category IN ('exact', 'near')"):
        total += 1
        r = json.loads(g['reasons_json'] or '{}')
        if (r.get('keeper') or [''])[0] == 'chosen by you':
            chosen += 1
        elif (r.get('margin') or 0) >= 0.12:
            decided += 1

    tiers = focus_tiers(conn)
    blurry = [i for i, t in tiers.items() if t['tier'] == 'blurry']
    days = conn.execute("SELECT COUNT(DISTINCT day) FROM events").fetchone()[0]
    events = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
    described = conn.execute(
        f"SELECT COUNT(DISTINCT a.sha256) FROM assets a JOIN ai_annotations x ON x.sha256 = a.sha256 "
        f"WHERE {present} AND x.error IS NULL AND COALESCE(x.description, '') != ''").fetchone()[0]
    share = settings.load().get('ai_gpu_share') or 30
    left = max(0, images - described)
    minutes = -(-left * SECONDS_PER_DESCRIPTION * 30 // share // 60) if left else 0
    exported = conn.execute("SELECT done FROM workflow WHERE step = 'export'").fetchone()
    people = conn.execute('SELECT COUNT(*) FROM sources').fetchone()[0]
    top = [r[0] for r in conn.execute(
        f"SELECT p.label FROM assets a JOIN places p ON p.asset_id = a.id WHERE {present} AND p.precision = 'in' "
        "GROUP BY p.label ORDER BY COUNT(*) DESC LIMIT 3")] if _has(conn, 'places') else []
    span = conn.execute("SELECT MIN(day), MAX(day) FROM events WHERE day != 'unknown'").fetchone()
    return {
        'analysing': bool(job and job.get('running')),
        'facts': {'photos': photos, 'videos': videos, 'people': people, 'days': days, 'places': top,
                  'start': span[0], 'end': span[1]},
        'clocks': {'devices': len(clocks), 'pending': pending, 'applied': applied},
        'moments': {'total': total, 'decided': decided, 'chosen': chosen, 'need_you': total - decided - chosen},
        'blurry': {'total': len(blurry), 'left_out': sum(1 for i in blurry if i in rejected),
                   'kept_favourites': sum(1 for i in blurry if i in favourite and i not in rejected)},
        'events': {'events': events, 'days': days},
        'descriptions': {'done': described, 'photos': images, 'minutes_left': minutes},
        'export': {'done': bool(exported and exported[0]), 'photos': photos - len(rejected)},
    }


def _has(conn, table: str) -> bool:
    return conn.execute("SELECT 1 FROM sqlite_master WHERE name = ?", (table,)).fetchone() is not None

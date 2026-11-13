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
COUNT_LIMIT = 20000      # files counted per folder for the wizard; beyond this it shows "20000+"
GENERIC_FOLDERS = {'dcim', 'camera', 'photos', 'pictures', 'images', 'export', 'exports', 'img', 'download',
                   'downloads', 'desktop', 'new folder', 'untitled folder', 'fotografije', 'slike', 'nova mapa',
                   # device names say which camera, not whose photos
                   'iphone', 'ipad', 'android', 'phone', 'telefon', 'sony', 'canon', 'nikon', 'fuji', 'fujifilm',
                   'gopro', 'dji', 'drone', 'pixel', 'samsung'}
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
    try:
        proc = subprocess.run(args, input='\n'.join(paths), capture_output=True, text=True, timeout=120)
        return json.loads(proc.stdout or '[]')
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return []                       # suggestions are optional: the folder name still works


def _clean_folder_name(path: str) -> str:
    name = os.path.basename(os.path.normpath(path)).strip()
    return '' if name.lower() in GENERIC_FOLDERS or name.isdigit() else name


def suggest(paths: list[str]) -> dict:
    remembered = settings.load().get('device_owners') or {}
    from itertools import islice
    from app.collections import data_dir
    data = os.path.realpath(data_dir())
    folders, rejected, seen, places, days = [], [], set(), [], []
    real = {str(raw): os.path.realpath(str(raw)) for raw in paths if str(raw).strip()}
    for raw in paths:
        if not str(raw).strip():
            rejected.append({'path': str(raw), 'problem': 'not found'})
            continue
        path = real[str(raw)]
        if path in seen:
            continue
        seen.add(path)
        inside = lambda a, b: a == b or a.startswith(b.rstrip(os.sep) + os.sep)
        if inside(path, data) or inside(data, path):
            rejected.append({'path': raw, 'problem': "the app's own data folder"})
            continue
        if any(other != path and inside(path, other) for other in real.values()):
            rejected.append({'path': raw, 'problem': 'inside another folder of this album'})
            continue
        if not os.path.exists(path):
            rejected.append({'path': raw, 'problem': 'not found'})
            continue
        if not os.path.isdir(path):
            rejected.append({'path': raw, 'problem': 'not a folder'})
            continue
        files = [f for f, _ in islice(walk_source(path), COUNT_LIMIT + 1)]
        more = len(files) > COUNT_LIMIT
        files = files[:COUNT_LIMIT]
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
        folders.append({'path': path, 'count': len(files), 'more': more, 'owner': owner, 'owner_from': source or None,
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
    images_all = conn.execute(f"SELECT COUNT(*) FROM assets a WHERE {present} AND kind = 'image'").fetchone()[0]
    # The same picture in two folders (AirDrop) is described once.
    images = conn.execute(f"SELECT COUNT(DISTINCT sha256) FROM assets a WHERE {present} AND kind = 'image'").fetchone()[0]
    videos = photos - images_all
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
    plan = _plan(conn)
    top = [r[0] for r in conn.execute(
        f"SELECT p.label FROM assets a JOIN places p ON p.asset_id = a.id WHERE {present} AND p.precision = 'in' "
        "GROUP BY p.label ORDER BY COUNT(*) DESC LIMIT 3")] if _has(conn, 'places') else []
    span = conn.execute("SELECT MIN(day), MAX(day) FROM events WHERE day != 'unknown'").fetchone()
    return {
        'analysing': bool(job and job.get('running') and job.get('kind') in (None, 'analysis')),
        'facts': {'photos': photos, 'videos': videos, 'people': people, 'days': days, 'places': top,
                  'start': span[0], 'end': span[1]},
        'clocks': {'devices': len(clocks), 'pending': pending, 'applied': applied},
        'moments': {'total': total, 'decided': decided, 'chosen': chosen, 'need_you': total - decided - chosen},
        'blurry': {'total': len(blurry), 'left_out': sum(1 for i in blurry if i in rejected),
                   'kept_favourites': sum(1 for i in blurry if i in favourite and i not in rejected)},
        'events': {'events': events, 'days': days},
        'descriptions': {'done': described, 'photos': images, 'minutes_left': minutes},
        'export': {'done': bool(exported and exported[0]), 'photos': plan['files'] if plan else 0},
        **_album_summary(conn, plan),
    }


def _plan(conn):
    """The plan "Export for Google Photos" will copy, or None when it cannot be built."""
    from app.organization.export_plan import google_photos_options, plan_export
    try:
        return plan_export(conn, **google_photos_options())
    except Exception:
        return None


def _album_summary(conn, plan) -> dict:
    """funnel, people, cover_id, highlights (M9), all derived from the same plan as the export.

    funnel: taken == left_out + blurry + extra_frames + in_album. Every present file is counted once; a paired
    secondary (Live Photo video, RAW/JPEG partner) follows its primary (see export_plan). The Google Photos preset
    uses selection 'no_blurry', so the plan's 'not_selected' is 0; it is added to 'blurry' to keep the identity.
    """
    if plan is None:
        funnel = {'taken': 0, 'left_out': 0, 'blurry': 0, 'extra_frames': 0, 'in_album': 0}
        return {'funnel': funnel, 'people': [], 'cover_id': None, 'highlights': []}
    c = plan['counts']
    funnel = {'taken': c['taken'], 'left_out': c['left_out'], 'blurry': c['blurry'] + c['not_selected'],
              'extra_frames': c['extra_frames'], 'in_album': c['in_album']}
    in_album = {e['asset_id'] for e in plan['entries']}
    taken_by, album_by = Counter(), Counter()
    for r in conn.execute("SELECT id, source_id FROM assets WHERE status = 'present'"):
        taken_by[r['source_id']] += 1
        album_by[r['source_id']] += r['id'] in in_album
    people = [{'owner': r['owner'], 'source_id': r['id'], 'taken': taken_by[r['id']], 'in_album': album_by[r['id']]}
              for r in conn.execute('SELECT id, owner FROM sources ORDER BY id')]
    cover_id, highlights = _cover_and_highlights(conn, in_album)
    return {'funnel': funnel, 'people': people, 'cover_id': cover_id, 'highlights': highlights}


HIGHLIGHTS = 12
PER_EVENT = 2


def _cover_and_highlights(conn, in_album: set):
    """Ranked with the same scores and weights as Best photos, restricted to photos in the album."""
    from app.quality.scoring import best_photos
    if not in_album:
        return None, []
    marks = {r['sha256'] for r in conn.execute('SELECT sha256 FROM marks WHERE favorite = 1')}
    favourite = {r['id'] for r in conn.execute("SELECT id, sha256 FROM assets WHERE status = 'present'")
                 if r['sha256'] in marks}
    ranked = [b for b in best_photos(conn, settings.load()['rank_weights'], 1_000_000, frozenset(favourite))
              if b['id'] in in_album]
    cover = next((b['id'] for b in ranked if b['id'] in favourite), ranked[0]['id'] if ranked else None)
    if cover is None:                    # nothing is scored yet: a favourite, else the first photo in the album
        first = [r['id'] for r in conn.execute(
            "SELECT id FROM assets WHERE status = 'present' AND kind = 'image' ORDER BY id") if r['id'] in in_album]
        cover = next((i for i in first if i in favourite), first[0] if first else None)
    event_of = {r['asset_id']: r['event_id'] for r in conn.execute('SELECT asset_id, event_id FROM event_members')}
    per_event, chosen = Counter(), []
    for b in ranked:
        ev = event_of.get(b['id'])
        if per_event[ev] >= PER_EVENT:
            continue
        per_event[ev] += 1
        chosen.append(b['id'])
        if len(chosen) == HIGHLIGHTS:
            break
    when = {r['id']: r['t'] for r in conn.execute(
        "SELECT a.id, c.sort_key + COALESCE(cc.applied_s, 0) AS t FROM assets a "
        "LEFT JOIN capture_time c ON c.asset_id = a.id "
        "LEFT JOIN clocks k ON k.source_id = a.source_id AND k.make = COALESCE(a.make, '') "
        "  AND k.model = COALESCE(a.model, '') "
        "LEFT JOIN clock_corrections cc ON cc.clock_id = k.id WHERE a.status = 'present'")}
    chosen.sort(key=lambda i: (when.get(i) is None, when.get(i) or 0, i))
    return cover, chosen


def _has(conn, table: str) -> bool:
    return conn.execute("SELECT 1 FROM sqlite_master WHERE name = ?", (table,)).fetchone() is not None

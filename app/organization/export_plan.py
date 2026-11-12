"""Smart export: deterministic names and folders (brief sections 8, 9, 16).

plan_export() builds the full list of (source -> new relative path) without
touching any file, so the page can show a preview. run_export() hands the same
plan to app/safety/safe_export.py, which copies original bytes into a new job
folder, verifies every copy and writes manifest.json (source path, new path,
checksums), which is also the reversible rename record.

Names
  default   2026-10-28_11-02-02_Florence_morning_001.HEIC
  original  20261028_110202_IMG_0581.HEIC
  place     2026-10-28_Florence_001.HEIC
  trip      Tuscany-2026_Day-6_Florence-morning_001.HEIC
Folders
  day       2026-10-28_Florence/            (date + most common place of the day)
  date      2026-10-28/
  event     2026-10-28/Florence, morning/
  place     Italy/Florence/
  flat      one folder
Duplicates (non-keepers of exact/near groups): skip, include, or put into
Alternatives/ next to Selected/ (the brief's "curated" output).

Facts only: the time is the resolved capture time with accepted clock
corrections; the place comes from GPS; "near X" stays "near-X"; a photo
without a trustworthy time goes to "undated" and keeps its original name
after the prefix "undated_" (documented fallback, never an invented date).
Live Photo, RAW+JPEG and same-name image+video pairs share one name stem.
"""
from __future__ import annotations

import os
import re
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime, timedelta

TEMPLATES = ('default', 'original', 'place', 'trip')
FOLDERS = ('day', 'date', 'event', 'place', 'flat')
DUPLICATES = ('skip', 'alternatives', 'include')
INVALID = re.compile(r'[\\/:*?"<>|\x00-\x1f]')


def clean_part(text: str, maxlen: int = 60) -> str:
    """Filename-safe, keeps Unicode letters (Žaž, Firenze), spaces become dashes."""
    text = unicodedata.normalize('NFC', str(text or '')).strip()
    text = INVALID.sub('', text)
    text = re.sub(r'[\s,;]+', '-', text)
    text = re.sub(r'-{2,}', '-', text).strip('-._')
    return text[:maxlen].rstrip('-._')


def _place_part(r) -> str:
    if not r['place_label']:
        return ''
    if r['place_precision'] == 'in':
        return r['place_name'] or r['place_label']
    if r['place_precision'] == 'near':
        return f"near {r['place_name']}"
    return r['region'] or r['place_label']


def _event_part(r, place: str) -> str:
    name = r['event_name'] or ''
    if r['event_source'] == 'auto' and r['event_place'] and name.startswith(r['event_place']):
        name = name[len(r['event_place']):].lstrip(' ,')          # "Florence, morning" -> "morning"
    return name


def _rows(conn):
    return conn.execute(
        "SELECT a.id, a.filename, a.ext, a.kind, a.size, a.sha256, a.source_id, s.path || '/' || a.rel_path AS path, "
        'c.local_time, c.confidence, c.sort_key + COALESCE(cc.applied_s, 0) AS t, COALESCE(cc.applied_s, 0) AS shift, '
        'p.name AS place_name, p.label AS place_label, p.precision AS place_precision, p.region, p.country, '
        'e.id AS event_id, e.name AS event_name, e.name_source AS event_source, e.place_label AS event_place, e.day '
        'FROM assets a JOIN sources s ON s.id = a.source_id '
        'LEFT JOIN capture_time c ON c.asset_id = a.id '
        "LEFT JOIN clocks k ON k.source_id = a.source_id AND k.make = COALESCE(a.make, '') "
        "  AND k.model = COALESCE(a.model, '') "
        'LEFT JOIN clock_corrections cc ON cc.clock_id = k.id '
        'LEFT JOIN places p ON p.asset_id = a.id '
        'LEFT JOIN event_members em ON em.asset_id = a.id LEFT JOIN events e ON e.id = em.event_id '
        "WHERE a.status = 'present' ORDER BY t IS NULL, t, a.source_id, a.rel_path").fetchall()


def _local_dt(r):
    if not r['local_time'] or r['confidence'] == 'unknown':
        return None
    return datetime.fromisoformat(r['local_time']) + timedelta(seconds=r['shift'] or 0)


def _pairs(conn):
    """secondary asset id -> primary asset id (files that must share a name)."""
    out = {}
    for r in conn.execute("SELECT kind, asset_a, asset_b FROM relationships "
                          "WHERE kind IN ('live_photo', 'raw_jpeg', 'live_photo_candidate')"):
        a, b = r['asset_a'], r['asset_b']
        if r['kind'] == 'raw_jpeg':
            a, b = min(a, b), max(a, b)
        out.setdefault(b, a)
    return out


def _non_keepers(conn):
    return {r[0] for r in conn.execute(
        'SELECT m.asset_id FROM duplicate_members m JOIN duplicate_groups g ON g.id = m.group_id '
        "WHERE g.category IN ('exact', 'near') AND g.keeper_id IS NOT NULL AND g.keeper_id != m.asset_id")}


def plan_export(conn, template: str = 'default', folders: str = 'day', duplicates: str = 'skip') -> dict:
    if template not in TEMPLATES:
        raise ValueError(f'template must be one of {TEMPLATES}')
    if folders not in FOLDERS:
        raise ValueError(f'folders must be one of {FOLDERS}')
    if duplicates not in DUPLICATES:
        raise ValueError(f'duplicates must be one of {DUPLICATES}')
    trip = clean_part(conn.execute('SELECT name FROM collection WHERE id = 1').fetchone()[0]) or 'Collection'
    rows = _rows(conn)
    pairs = _pairs(conn)
    skip_dups = _non_keepers(conn)
    days = sorted({_local_dt(r).date() for r in rows if _local_dt(r)})
    day_no = {d: (d - days[0]).days + 1 for d in days}          # calendar days since the first photo
    day_place = {}
    for d in days:
        c = Counter(r['place_name'] for r in rows if _local_dt(r) and _local_dt(r).date() == d
                    and r['place_precision'] == 'in' and r['place_name'])
        day_place[d] = c.most_common(1)[0][0] if c else ''

    primary_rows = [r for r in rows if r['id'] not in pairs]
    by_id = {r['id']: r for r in rows}
    seq = defaultdict(int)
    stems = {}
    entries, warnings = [], Counter()

    def folder_for(r, dt):
        top = []
        if duplicates == 'alternatives':
            top = ['Alternatives' if r['id'] in skip_dups else 'Selected']
        if dt is None:
            return top + ['undated'] if folders != 'flat' else top
        d = dt.date().isoformat()
        if folders == 'day':
            return top + [clean_part(f'{d}_{day_place[dt.date()]}' if day_place[dt.date()] else d)]
        if folders == 'date':
            return top + [d]
        if folders == 'event':
            return top + [d, clean_part(r['event_name'] or 'Other', 80)]
        if folders == 'place':
            if not r['place_label']:
                return top + ['Unknown place']
            city = r['place_name'] if r['place_precision'] in ('in', 'near') else (r['region'] or 'Unknown place')
            return top + [clean_part(r['country'] or 'Unknown country'), clean_part(city)]
        return top

    for r in primary_rows:
        if duplicates == 'skip' and r['id'] in skip_dups:
            warnings['duplicates skipped'] += 1
            continue
        dt = _local_dt(r)
        folder = '/'.join(folder_for(r, dt))
        stem_original = clean_part(os.path.splitext(r['filename'])[0], 80) or 'file'
        if dt is None:
            stem = f'undated_{stem_original}'
            warnings['no trustworthy capture time'] += 1
        else:
            seq[folder] += 1
            n = f'{seq[folder]:03d}'
            place = clean_part(_place_part(r))
            event = clean_part(_event_part(r, place))
            if not r['place_label']:
                warnings['no place (no GPS)'] += 1
            if template == 'default':
                parts = [dt.strftime('%Y-%m-%d_%H-%M-%S'), place, event, n]
            elif template == 'original':
                parts = [dt.strftime('%Y%m%d_%H%M%S'), stem_original]
            elif template == 'place':
                parts = [dt.strftime('%Y-%m-%d'), place, n]
            else:
                parts = [trip, f'Day-{day_no[dt.date()]}', clean_part(r['event_name'] or ''), n]
            stem = '_'.join(p for p in parts if p)
        stems[r['id']] = (folder, stem)
        entries.append(_entry(r, folder, stem, r['id'] in skip_dups))

    for sec, pri in pairs.items():
        r = by_id.get(sec)
        if r is None:
            continue
        if pri not in stems:              # its partner was skipped as a duplicate: skip it too
            continue
        folder, stem = stems[pri]
        entries.append(_entry(r, folder, stem, False, paired_with=pri))
        warnings['paired files kept together'] += 1

    entries.sort(key=lambda e: (e['dest'].lower()))
    total = sum(e['size'] for e in entries)
    return {'trip': trip, 'template': template, 'folders': folders, 'duplicates': duplicates,
            'files': len(entries), 'bytes': total, 'folders_count': len({os.path.dirname(e['dest']) for e in entries}),
            'warnings': dict(warnings), 'entries': entries}


def _entry(r, folder, stem, alternative, paired_with=None):
    ext = os.path.splitext(r['filename'])[1] or r['ext']          # original case kept (.HEIC stays .HEIC)
    dest = f'{folder}/{stem}{ext}' if folder else f'{stem}{ext}'
    return {'asset_id': r['id'], 'source': r['path'], 'original_name': r['filename'], 'dest': dest,
            'size': r['size'], 'sha256': r['sha256'], 'alternative': alternative, 'paired_with': paired_with}


def run_export(conn, dest_root: str, plan: dict, resume_dir: str | None = None, progress=None):
    from app.safety.safe_export import ExportItem, export_copies
    items = [ExportItem(source=e['source'], dest_name=e['dest']) for e in plan['entries']]
    roots = sorted({r[0] for r in conn.execute('SELECT path FROM sources')})
    return export_copies(items, dest_root, roots, plan['trip'], resume_dir=resume_dir, progress=progress,
                         extra={'plan': {k: plan[k] for k in ('template', 'folders', 'duplicates', 'files', 'bytes')},
                                'original_names': {e['dest']: e['original_name'] for e in plan['entries']}})

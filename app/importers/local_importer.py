"""Index local folders into a collection. Read-only by construction.

Source files are only opened with mode 'rb' (for SHA-256) and passed to
ExifTool for reading. Nothing is created, renamed or modified inside a source
folder; everything the importer produces goes into the collection database.

Re-indexing is incremental: a file whose size and mtime are unchanged is not
re-hashed or re-read. Files that disappeared are marked 'missing', not deleted.
"""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
from collections import Counter
from pathlib import Path
from typing import Callable, Optional

from app.collections import now_iso
from app.metadata.exif_reader import first, read_metadata
from app.metadata.timestamp_resolver import explicit_offset, parse_offset, resolve

IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp', '.webp',
              '.heic', '.heif', '.hif', '.avif', '.dng', '.cr2', '.cr3', '.crw',
              '.nef', '.nrw', '.arw', '.srf', '.sr2', '.raf', '.orf', '.rw2',
              '.pef', '.srw', '.x3f', '.3fr', '.erf', '.kdc', '.mos', '.mrw', '.iiq', '.rwl'}
RAW_EXTS = IMAGE_EXTS - {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp', '.webp',
                         '.heic', '.heif', '.hif', '.avif'}
VIDEO_EXTS = {'.mov', '.mp4', '.m4v', '.3gp', '.avi', '.mts', '.m2ts', '.mkv'}
CHUNK = 1024 * 1024

Progress = Callable[[str, int, int], None]


def kind_of(ext: str) -> Optional[str]:
    ext = ext.lower()
    if ext in IMAGE_EXTS:
        return 'image'
    if ext in VIDEO_EXTS:
        return 'video'
    return None


def walk_source(root: str):
    """Yield (abs_path, rel_path) of media files. Skips hidden files/folders,
    AppleDouble '._' files and symlinks that point outside the source."""
    root_real = os.path.realpath(root)
    for dirpath, dirnames, filenames in os.walk(root_real, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith('.'))
        for name in sorted(filenames):
            if name.startswith('.'):
                continue
            if kind_of(os.path.splitext(name)[1]) is None:
                continue
            full = os.path.join(dirpath, name)
            if os.path.islink(full):
                target = os.path.realpath(full)
                if not (target.startswith(root_real + os.sep) and os.path.isfile(target)):
                    continue
            yield full, os.path.relpath(full, root_real)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(CHUNK), b''):
            h.update(chunk)
    return h.hexdigest()


def index_source(conn: sqlite3.Connection, source_id: int,
                 progress: Optional[Progress] = None, cancelled: Callable[[], bool] = lambda: False) -> dict:
    src = conn.execute('SELECT * FROM sources WHERE id = ?', (source_id,)).fetchone()
    root = src['path']
    if not os.path.isdir(root):
        raise FileNotFoundError(f'source folder not found: {root}')
    known = {r['rel_path']: r for r in conn.execute(
        'SELECT id, rel_path, size, mtime, status FROM assets WHERE source_id = ?', (source_id,))}
    files = list(walk_source(root))
    seen, todo = set(), []
    stats = {'files': len(files), 'new': 0, 'changed': 0, 'unchanged': 0, 'missing': 0, 'errors': 0}
    for full, rel in files:
        seen.add(rel)
        st = os.stat(full)
        old = known.get(rel)
        if old and old['size'] == st.st_size and abs(old['mtime'] - st.st_mtime) < 1e-6 \
                and old['status'] == 'present':
            stats['unchanged'] += 1
            continue
        todo.append((full, rel, st, old))

    # Hash first (cancellable), then read metadata in ExifTool batches.
    hashed = []
    for i, (full, rel, st, old) in enumerate(todo):
        if cancelled():
            break
        if progress:
            progress(f'Hashing {rel}', i, len(todo))
        try:
            hashed.append((full, rel, st, old, sha256_file(full), None))
        except OSError as e:
            hashed.append((full, rel, st, old, '', str(e)))
            stats['errors'] += 1
    if progress and hashed:
        progress('Reading metadata', len(hashed), len(todo))
    meta, reader = read_metadata([h[0] for h in hashed]) if hashed else ({}, '')

    ts = now_iso()
    with conn:
        for full, rel, st, old, digest, err in hashed:
            tags = meta.get(full, {})
            ext = os.path.splitext(rel)[1].lower()
            row = dict(
                source_id=source_id, rel_path=rel, filename=os.path.basename(rel), ext=ext,
                kind=kind_of(ext), size=st.st_size, mtime=st.st_mtime, sha256=digest,
                make=first(tags, 'EXIF:Make', 'QuickTime:Make', 'Make'),
                model=first(tags, 'EXIF:Model', 'QuickTime:Model', 'Model'),
                lens=first(tags, 'EXIF:LensModel', 'LensModel'),
                width=_int(first(tags, 'File:ImageWidth', 'EXIF:ExifImageWidth', 'QuickTime:ImageWidth', 'ImageWidth')),
                height=_int(first(tags, 'File:ImageHeight', 'EXIF:ExifImageHeight', 'QuickTime:ImageHeight', 'ImageHeight')),
                gps_lat=_float(first(tags, 'Composite:GPSLatitude', 'EXIF:GPSLatitude', 'GPSLatitude')),
                gps_lon=_float(first(tags, 'Composite:GPSLongitude', 'EXIF:GPSLongitude', 'GPSLongitude')),
                indexed_at=ts, error=err, status='present')
            if old:
                stats['changed'] += 1
                conn.execute(f"UPDATE assets SET {', '.join(f'{k} = :{k}' for k in row)} WHERE id = :id",
                             {**row, 'id': old['id']})
                asset_id = old['id']
            else:
                stats['new'] += 1
                cur = conn.execute(f"INSERT INTO assets ({', '.join(row)}) VALUES ({', '.join(':' + k for k in row)})", row)
                asset_id = cur.lastrowid
            conn.execute('INSERT INTO metadata_raw (asset_id, reader, tags_json) VALUES (?, ?, ?) '
                         'ON CONFLICT(asset_id) DO UPDATE SET reader = excluded.reader, tags_json = excluded.tags_json',
                         (asset_id, reader, json.dumps(tags, ensure_ascii=False, default=str)))
        if not cancelled():
            gone = [r['id'] for rel, r in known.items() if rel not in seen and r['status'] == 'present']
            stats['missing'] = len(gone)
            conn.executemany("UPDATE assets SET status = 'missing' WHERE id = ?", [(g,) for g in gone])
            conn.execute('UPDATE sources SET last_indexed_at = ? WHERE id = ?', (ts, source_id))
    stats['cancelled'] = cancelled()
    stats['reader'] = reader
    return stats


def resolve_all(conn: sqlite3.Connection) -> dict:
    """(Re)compute capture times for every asset of the collection.

    Runs after indexing because an assumed offset depends on the other files
    of the same source. Cheap: no file access, only stored metadata."""
    tz_row = conn.execute('SELECT timezone FROM collection WHERE id = 1').fetchone()
    coll_tz = tz_row['timezone'] if tz_row else None
    rows = conn.execute(
        'SELECT a.id, a.source_id, a.filename, a.mtime, a.kind, s.owner, m.tags_json '
        'FROM assets a JOIN sources s ON s.id = a.source_id '
        "LEFT JOIN metadata_raw m ON m.asset_id = a.id WHERE a.status = 'present'").fetchall()
    tags_by_id = {r['id']: json.loads(r['tags_json'] or '{}') for r in rows}

    per_source: dict[int, Counter] = {}
    for r in rows:
        off = explicit_offset(tags_by_id[r['id']])
        if off is not None:
            per_source.setdefault(r['source_id'], Counter())[off] += 1

    coll_offset = parse_offset(coll_tz) if coll_tz else None
    counts = Counter()
    with conn:
        for r in rows:
            c = per_source.get(r['source_id'])
            if c:
                off, n = c.most_common(1)[0]
                why = (f'most common offset among {sum(c.values())} files of source "{r["owner"]}" '
                       f'({n} of them)')
            elif coll_offset is not None:
                off, why = coll_offset, f'collection time zone {coll_tz}'
            else:
                off, why = None, ''
            res = resolve(tags_by_id[r['id']], r['filename'], r['mtime'], r['kind'] or 'image', off, why)
            counts[res.confidence] += 1
            conn.execute(
                'INSERT INTO capture_time (asset_id, local_time, utc_time, offset_minutes, rule, confidence, '
                'notes_json, sort_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
                'ON CONFLICT(asset_id) DO UPDATE SET local_time = excluded.local_time, '
                'utc_time = excluded.utc_time, offset_minutes = excluded.offset_minutes, rule = excluded.rule, '
                'confidence = excluded.confidence, notes_json = excluded.notes_json, sort_key = excluded.sort_key',
                (r['id'], res.local_time, res.utc_time, res.offset_minutes, res.rule, res.confidence,
                 json.dumps(res.notes, ensure_ascii=False), res.sort_key))
    return dict(counts)


def link_relationships(conn: sqlite3.Connection) -> dict:
    """Live Photo pairs (same ContentIdentifier) and RAW+JPEG pairs (same folder
    and file stem). Pairs are only recorded; no file is hidden or dropped."""
    rows = conn.execute(
        'SELECT a.id, a.source_id, a.rel_path, a.ext, a.kind, m.tags_json FROM assets a '
        "LEFT JOIN metadata_raw m ON m.asset_id = a.id WHERE a.status = 'present'").fetchall()
    pairs = []
    by_cid: dict[str, dict] = {}
    by_stem: dict[tuple, list] = {}
    for r in rows:
        tags = json.loads(r['tags_json'] or '{}')
        cid = first(tags, 'MakerNotes:ContentIdentifier', 'QuickTime:ContentIdentifier', 'ContentIdentifier')
        if cid:
            by_cid.setdefault(str(cid), {}).setdefault(r['kind'], []).append(r['id'])
        stem = os.path.splitext(r['rel_path'])[0].lower()
        by_stem.setdefault((r['source_id'], stem), []).append(r)
    live_ids = set()
    for cid, kinds in by_cid.items():
        for img in kinds.get('image', []):
            for vid in kinds.get('video', []):
                pairs.append(('live_photo', img, vid, f'ContentIdentifier {cid}'))
                live_ids.update((img, vid))
    for (_, stem), group in by_stem.items():
        raws = [g for g in group if g['ext'] in RAW_EXTS]
        jpgs = [g for g in group if g['kind'] == 'image' and g['ext'] not in RAW_EXTS]
        vids = [g for g in group if g['kind'] == 'video']
        for a in raws:
            for b in jpgs:
                pairs.append(('raw_jpeg', a['id'], b['id'], 'same folder and file name'))
        for a in jpgs + raws:
            for b in vids:
                if a['id'] not in live_ids and b['id'] not in live_ids:
                    pairs.append(('live_photo_candidate', a['id'], b['id'],
                                  'same folder and file name, no ContentIdentifier'))
    with conn:
        conn.execute('DELETE FROM relationships')
        conn.executemany('INSERT OR IGNORE INTO relationships (kind, asset_a, asset_b, evidence) '
                         'VALUES (?, ?, ?, ?)', pairs)
    return dict(Counter(p[0] for p in pairs))


def index_collection(conn: sqlite3.Connection, progress: Optional[Progress] = None,
                     cancelled: Callable[[], bool] = lambda: False) -> dict:
    out = {'sources': {}}
    for s in conn.execute('SELECT id, path, owner FROM sources ORDER BY id').fetchall():
        if cancelled():
            break
        step = (lambda msg, i, n, o=s['owner']: progress(f'[{o}] {msg}', i, n)) if progress else None
        out['sources'][s['owner'] + ' · ' + s['path']] = index_source(conn, s['id'], step, cancelled)
    if progress:
        progress('Resolving capture times', 0, 0)
    out['confidence'] = resolve_all(conn)
    out['relationships'] = link_relationships(conn)
    return out


def _int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def _float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

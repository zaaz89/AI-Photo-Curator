"""Write corrected time, place, description and favourite into EXPORTED COPIES.

Owner's decision 2026-11-12: Google Photos only shows what is inside the file,
so the "Export for Google Photos" copies get:
  DateTimeOriginal / OffsetTimeOriginal  when a clock correction was applied or the
                                         file had no offset but the app resolved one
  XMP dc:description + EXIF ImageDescription   the AI description (if any)
  XMP photoshop:City / Country           city only when the photo is in the place (not "near"), country from GPS
  XMP Rating = 5                         favourites
Originals are never touched: every target must be inside the export job folder and
must not be a source file. Only photos are written; videos are copied unchanged.
After writing, the tags are read back and compared; the manifest records it.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from app.metadata.exif_reader import exiftool_path

PHOTO_EXTS = {'.jpg', '.jpeg', '.heic', '.heif', '.hif', '.tif', '.tiff', '.png', '.dng', '.webp'}


def _inside(path: str, folder: str) -> bool:
    p, f = os.path.realpath(path), os.path.realpath(folder)
    return p.startswith(f.rstrip(os.sep) + os.sep)


def tag_args(meta: dict) -> list[str]:
    args = []
    if meta.get('datetime'):
        args.append(f"-EXIF:DateTimeOriginal={meta['datetime']}")
        if meta.get('offset'):
            args += [f"-EXIF:OffsetTimeOriginal={meta['offset']}", f"-EXIF:OffsetTime={meta['offset']}"]
    if meta.get('description'):
        d = meta['description'].replace('\n', ' ')
        args += [f'-XMP-dc:Description={d}', f'-EXIF:ImageDescription={d}']
    if meta.get('city'):
        args.append(f"-XMP-photoshop:City={meta['city']}")
    if meta.get('country'):
        args.append(f"-XMP-photoshop:Country={meta['country']}")
    if meta.get('favorite'):
        args.append('-XMP-xmp:Rating=5')
    return args


def write_into_copies(job_dir: str, items: list[dict], source_roots: list[str]) -> dict:
    """items: [{'dest': path, 'meta': {...}}]. Returns counts; updates items in place."""
    exe = exiftool_path()
    if not exe:
        return {'skipped': 'ExifTool not installed'}
    roots = [os.path.realpath(r) for r in source_roots]
    written = verified = failed = 0
    todo = []
    for it in items:
        dest, meta = it['dest'], it.get('meta') or {}
        if Path(dest).suffix.lower() not in PHOTO_EXTS or not tag_args(meta):
            continue
        real = os.path.realpath(dest)
        if not _inside(real, job_dir) or any(real == r or real.startswith(r + os.sep) for r in roots):
            it['metadata_error'] = 'refused: not inside the export folder'
            failed += 1
            continue
        todo.append(it)
    for it in todo:
        args = [exe, '-q', '-q', '-overwrite_original', '-P', '-charset', 'filename=utf8',
                *tag_args(it['meta']), it['dest']]
        proc = subprocess.run(args, capture_output=True, text=True, timeout=120)
        if proc.returncode != 0:
            it['metadata_error'] = (proc.stderr or 'exiftool failed').strip()[:300]
            failed += 1
            continue
        written += 1
        back = subprocess.run([exe, '-j', '-charset', 'filename=utf8', '-EXIF:DateTimeOriginal', '-XMP-dc:Description',
                               it['dest']], capture_output=True, text=True, timeout=60)
        try:
            row = json.loads(back.stdout)[0]
        except (json.JSONDecodeError, IndexError):
            row = {}
        ok = True
        if it['meta'].get('datetime'):
            ok &= str(row.get('DateTimeOriginal', '')).startswith(it['meta']['datetime'])
        if it['meta'].get('description'):
            ok &= row.get('Description', '').strip() == it['meta']['description'].replace('\n', ' ').strip()
        it['metadata_written'] = it['meta']
        it['metadata_verified'] = bool(ok)
        verified += int(ok)
    return {'written': written, 'verified': verified, 'failed': failed}

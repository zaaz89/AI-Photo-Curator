"""Read metadata from photos and videos without modifying them.

Primary reader: ExifTool in batch mode (JSON, numeric values, family-0 group
prefixes such as "EXIF:", "QuickTime:", "MakerNotes:"). ExifTool reads HEIC,
RAW, MOV/MP4 and Apple's Live Photo ContentIdentifier. It is only ever called
with read options; no write flag is passed.

Fallback when ExifTool is missing: Pillow, images only, a subset of tags
mapped to the same "EXIF:Name" keys.
"""
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Iterable

TAGS = [
    'DateTimeOriginal', 'SubSecTimeOriginal', 'OffsetTimeOriginal',
    'CreateDate', 'SubSecTimeDigitized', 'OffsetTimeDigitized',
    'CreationDate', 'GPSDateTime', 'GPSLatitude', 'GPSLongitude',
    'Make', 'Model', 'LensModel', 'ImageWidth', 'ImageHeight',
    'ContentIdentifier', 'MIMEType', 'Duration',
]
BATCH = 200


def exiftool_path() -> str | None:
    return shutil.which('exiftool') or next(
        (p for p in ('/opt/homebrew/bin/exiftool', '/usr/local/bin/exiftool')
         if Path(p).exists()), None)


def exiftool_version() -> str | None:
    exe = exiftool_path()
    if not exe:
        return None
    try:
        return subprocess.run([exe, '-ver'], capture_output=True, text=True,
                              timeout=20).stdout.strip() or None
    except Exception:
        return None


def _read_exiftool(exe: str, paths: list[str]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for i in range(0, len(paths), BATCH):
        chunk = paths[i:i + BATCH]
        # Paths go through an argument file on stdin (-@ -) so names with
        # spaces, quotes or a leading dash are passed literally.
        args = [exe, '-json', '-n', '-G0', '-charset', 'filename=utf8',
                '-api', 'LargeFileSupport=1', '-q', '-q']
        args += [f'-{t}' for t in TAGS] + ['-@', '-']
        proc = subprocess.run(args, input='\n'.join(chunk), capture_output=True,
                              text=True, timeout=600)
        try:
            rows = json.loads(proc.stdout or '[]')
        except json.JSONDecodeError:
            rows = []
        for row in rows:
            src = row.pop('SourceFile', None)
            if src:
                out[src] = row
    return out


def _read_pillow(path: str) -> dict:
    from PIL import Image
    from PIL.ExifTags import TAGS as PTAGS, GPSTAGS
    try:
        from raw_loader import open_image_pil
        img = open_image_pil(path)
    except Exception:
        img = Image.open(path)
    tags: dict = {}
    with img:
        tags['File:ImageWidth'], tags['File:ImageHeight'] = img.size
        exif = img.getexif()
        merged = {PTAGS.get(k, k): v for k, v in exif.items()}
        try:
            merged.update({PTAGS.get(k, k): v for k, v in exif.get_ifd(0x8769).items()})
        except Exception:
            pass
        for name in ('DateTimeOriginal', 'SubSecTimeOriginal', 'OffsetTimeOriginal',
                     'CreateDate', 'DateTimeDigitized', 'Make', 'Model', 'LensModel'):
            if name in merged and merged[name] not in (None, ''):
                key = 'CreateDate' if name == 'DateTimeDigitized' else name
                tags[f'EXIF:{key}'] = str(merged[name]).strip('\x00 ')
    return tags


def read_metadata(paths: Iterable[str]) -> tuple[dict[str, dict], str]:
    """Return ({path: tags}, reader_name). Missing files map to {}."""
    paths = [str(p) for p in paths]
    exe = exiftool_path()
    if exe:
        found = _read_exiftool(exe, paths)
        reader = f'exiftool {exiftool_version() or "?"}'
        return {p: found.get(p, {}) for p in paths}, reader
    out = {}
    for p in paths:
        try:
            out[p] = _read_pillow(p)
        except Exception:
            out[p] = {}
    return out, 'pillow'


def first(tags: dict, *names: str):
    """First non-empty value among "Group:Name" keys or bare names (any group)."""
    for name in names:
        if ':' in name:
            v = tags.get(name)
            if v not in (None, ''):
                return v
        else:
            for k, v in tags.items():
                if k.split(':', 1)[-1] == name and v not in (None, ''):
                    return v
    return None

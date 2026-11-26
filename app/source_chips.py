"""Folder chips that tell folders apart (M14c).

Owner feedback (screenshot 2026-11-26): two folders both showed "Jarek Pawlak" and a third "Toskana 2026 …".
Root cause: the New Album suggestion takes the person from EXIF Artist / Copyright when nothing else is known
(`app/assistant.suggest`), and a hired photographer writes the same name into every file; the stage chip showed
only that name. "…" was the chip's only state for "no count yet".

A chip now says: the person (when the folder has one) and the camera ("Jarek Pawlak · Sony A7 IV"), the camera
alone when there is no person, the folder name as the last resort. Two chips with the same words get the folder
name instead of the camera, then a number. Camera names are the ones people know ("Sony A7 IV", not
"SONY ILCE-7M4"). Each folder also has a state: waiting, reading (n of m), read, empty (no photos found) or
failed (with the reason). Pure functions, so tests pin them.
"""
from __future__ import annotations

import os
import re
from collections import Counter

ROMAN = {'2': 'II', '3': 'III', '4': 'IV', '5': 'V', '6': 'VI'}
DROP_MAKE = ('apple', 'google')
MAKE_NAMES = {'sony': 'Sony', 'nikon corporation': 'Nikon', 'nikon': 'Nikon', 'canon': 'Canon',
              'fujifilm': 'Fujifilm', 'olympus corporation': 'Olympus', 'om digital solutions': 'OM System',
              'panasonic': 'Panasonic', 'samsung': 'Samsung', 'dji': 'DJI', 'gopro': 'GoPro', 'leica camera ag': 'Leica',
              'ricoh imaging company, ltd.': 'Ricoh', 'xiaomi': 'Xiaomi', 'huawei': 'Huawei', 'oneplus': 'OnePlus'}
_SONY = re.compile(r'^ILCE-(\d+)([A-Z]*?)(?:M(\d))?$')


def pretty_device(make, model) -> str:
    """'SONY', 'ILCE-7M4' -> 'Sony A7 IV'; 'Apple', 'iPhone 15 Pro' -> 'iPhone 15 Pro'; '' when unknown."""
    make, model = (make or '').strip(), (model or '').strip()
    brand = MAKE_NAMES.get(make.lower(), make.title() if make.isupper() else make)
    if model:
        m = _SONY.match(model.upper())
        if m and make.lower() in ('sony', ''):
            num, letters, gen = m.groups()
            name = f'A{num}{letters}' + (f' {ROMAN.get(gen, gen)}' if gen else '')
            return f'Sony {name}'
    if not model:
        return brand
    if make.lower() in DROP_MAKE or not make:
        return model
    model = re.sub(r'_(\d)$', lambda m: ' ' + ROMAN.get(m.group(1), m.group(1)), model)   # Nikon "Z 6_2"
    if model.lower().startswith(make.lower()) or model.lower().startswith(brand.lower()):
        rest = model[len(make):].strip() if model.lower().startswith(make.lower()) else model[len(brand):].strip()
        return f'{brand} {rest}'.strip()
    return f'{brand} {model}'


def folder_name(path: str) -> str:
    return os.path.basename(os.path.normpath(path or '')) or (path or '')


def chip_labels(sources: list[dict]) -> dict:
    """source id -> chip label. `sources`: dicts with id, owner, path, devices (pretty names, most photos first)."""
    def words(s, mode):
        person = (s.get('owner') or '').strip()
        devices = [d for d in (s.get('devices') or []) if d]
        device = devices[0] if devices else ''
        folder = folder_name(s.get('path') or '')
        if person.casefold() == folder.casefold():
            person = ''                  # the name was only the folder's (no person known): camera first
        parts = [person or device]
        if mode == 0:
            parts.append(device if person else folder)
        elif mode == 1:
            parts.append(folder)
        else:
            parts += [device if person else '', folder]
        out, seen = [], set()
        for x in parts:
            if x and x.casefold() not in seen:
                out.append(x)
                seen.add(x.casefold())
        return ' · '.join(out) or folder

    labels = {s['id']: words(s, 0) for s in sources}
    for mode in (1, 2):
        counts = Counter(v.casefold() for v in labels.values())
        clash = [s for s in sources if counts[labels[s['id']].casefold()] > 1]
        if not clash:
            break
        for s in clash:
            labels[s['id']] = words(s, mode)
    counts = Counter(v.casefold() for v in labels.values())
    seen: Counter = Counter()
    for s in sources:                     # still the same words (same person, camera and folder name): number them
        key = labels[s['id']].casefold()
        if counts[key] > 1:
            seen[key] += 1
            labels[s['id']] = f"{labels[s['id']]} ({seen[key]})"
    return labels


def source_state(source: dict, index: int, exists: bool, job: dict | None) -> dict:
    """What a folder's chip says while the album is built.

    source: id, assets (present photos). index: its place in the album's folder order (0-based).
    job: the engine job when it is this album's analysis and runs (with its `stage`), else None.
    -> {'state': waiting | reading | read | empty | failed, 'done', 'total', 'reason'?}"""
    assets = int(source.get('assets') or 0)
    if not exists:
        return {'state': 'failed', 'reason': 'folder not found', 'done': 0, 'total': 0}
    stage = (job or {}).get('stage') or {}
    if job and job.get('running') and stage.get('phase') == 'reading':
        current = stage.get('source_id')
        position = max(0, int(stage.get('source') or 1) - 1)
        if current == source['id']:
            return {'state': 'reading', 'done': int(stage.get('done') or 0), 'total': int(stage.get('total') or 0)}
        if index > position:
            return {'state': 'waiting', 'done': 0, 'total': 0}
    if job and job.get('running') and not stage and assets == 0:
        return {'state': 'waiting', 'done': 0, 'total': 0}
    if assets == 0:
        return {'state': 'empty', 'done': 0, 'total': 0}
    return {'state': 'read', 'done': assets, 'total': assets}

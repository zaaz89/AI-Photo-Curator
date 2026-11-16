"""How strictly photos count as blurry and eyes as closed (owner's setting `quality_strictness`, M11).

Normal is the calibrated behaviour (2026-11-16, the owner's 236 professional and 255 phone photos).
Lenient and strict move the same lines by a fixed step; they are not calibrated on their own.
Every verdict is made when results are read, so a change applies at once, without a new analysis.
"""
from __future__ import annotations

import os

LEVELS = {
    #            blur lines x   closed below   closed in a moment: share of the face's best / below
    'lenient': {'blur': 0.75, 'eye_closed': 0.09, 'rel_closed': 0.55, 'rel_max': 0.16},
    'normal':  {'blur': 1.0,  'eye_closed': 0.12, 'rel_closed': 0.65, 'rel_max': 0.20},
    'strict':  {'blur': 1.3,  'eye_closed': 0.15, 'rel_closed': 0.75, 'rel_max': 0.24},
}

_cache: dict = {}


def current() -> dict:
    """The lines of the owner's level (cached until the settings file changes)."""
    from app import settings
    path = settings._path()
    try:
        key = (str(path), os.stat(path).st_mtime_ns)
    except OSError:
        key = (str(path), None)
    if _cache.get('key') != key:
        level = settings.load().get('quality_strictness', 'normal')
        _cache.update(key=key, level=level if level in LEVELS else 'normal')
    return {'level': _cache['level'], **LEVELS[_cache['level']]}

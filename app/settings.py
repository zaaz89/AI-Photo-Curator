"""App-wide settings stored in local-data/settings.json (not in git)."""
from __future__ import annotations

import json

from app.collections import data_dir

DEFAULTS = {
    # Share of time the local AI may keep the GPU busy during long jobs.
    # 100 = no limit. Implemented as pauses between photos (macOS has no
    # per-process GPU cap).
    'ai_gpu_share': 30,
    # Pause long AI jobs while the Mac runs on battery.
    'ai_pause_on_battery': False,
    # Interface language: en (default, owner's choice 2026-11-12) or sl.
    'ui_language': 'en',
    # Best photos: weights of the five ranking categories (upstream defaults).
    'rank_weights': {'aesthetic': 30, 'composition': 22, 'technical': 20, 'sharpness': 16, 'color': 12},
    # Choosing the better of near-identical photos: faces (eyes open, looking at the camera,
    # face sharp), whole-frame focus, overall look, resolution.
    'keeper_weights': {'faces': 40, 'focus': 30, 'look': 20, 'resolution': 10},
}
CHOICES = {'ai_gpu_share': (25, 30, 50, 100), 'ui_language': ('en', 'sl')}


def _path():
    return data_dir() / 'settings.json'


def load() -> dict:
    out = dict(DEFAULTS)
    try:
        out.update({k: v for k, v in json.loads(_path().read_text()).items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    return out


def save(changes: dict) -> dict:
    cur = load()
    for k, v in changes.items():
        if k not in DEFAULTS:
            raise ValueError(f'unknown setting {k}')
        if k in CHOICES and v not in CHOICES[k]:
            raise ValueError(f'{k} must be one of {CHOICES[k]}')
        if isinstance(DEFAULTS[k], bool):
            v = bool(v)
        if k == 'keeper_weights':
            if not isinstance(v, dict) or any(c not in DEFAULTS['keeper_weights'] for c in v):
                raise ValueError('keeper_weights must map faces, focus, look, resolution to numbers')
            v = {c: max(0, min(100, int(v.get(c, 0)))) for c in DEFAULTS['keeper_weights']}
        if k == 'rank_weights':
            if not isinstance(v, dict) or any(c not in DEFAULTS['rank_weights'] for c in v):
                raise ValueError('rank_weights must map the five categories to numbers')
            v = {c: max(0, min(100, int(v.get(c, 0)))) for c in DEFAULTS['rank_weights']}
        cur[k] = v
    _path().parent.mkdir(parents=True, exist_ok=True)
    _path().write_text(json.dumps(cur, indent=2))
    return cur

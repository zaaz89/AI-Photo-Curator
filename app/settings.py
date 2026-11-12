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
}
CHOICES = {'ai_gpu_share': (25, 30, 50, 100)}


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
        cur[k] = v
    _path().parent.mkdir(parents=True, exist_ok=True)
    _path().write_text(json.dumps(cur, indent=2))
    return cur

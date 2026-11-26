"""Benchmark run of the whole analysis (M13, scripts/bench.sh): wall time per stage, peak memory of the engine
and of the Swift helper, photos per second and the GPU share the throttle really used.

Memory is sampled with `ps` every half second (macOS and Linux): the engine is this process plus its Python
children (process pools), the helper is every `pc-helper` process. A peak between two samples can be missed;
`ru_maxrss` of this process is reported as a cross-check.
"""
from __future__ import annotations

import json
import os
import platform
import resource
import subprocess
import sys
import threading
import time
from datetime import datetime


class RssSampler(threading.Thread):
    def __init__(self, interval: float = 0.5):
        super().__init__(daemon=True)
        self.interval = interval
        self.stop = threading.Event()
        self.engine_mb = 0.0
        self.helper_mb = 0.0
        self.samples = 0

    def _sample(self) -> None:
        try:
            out = subprocess.run(['ps', '-A', '-o', 'pid=,ppid=,rss=,comm='], capture_output=True, text=True,
                                 timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            return
        procs = []
        for line in out.splitlines():
            parts = line.split(None, 3)
            if len(parts) == 4 and parts[0].isdigit() and parts[1].isdigit() and parts[2].isdigit():
                procs.append((int(parts[0]), int(parts[1]), int(parts[2]), parts[3]))
        children = {}
        for pid, ppid, _, _ in procs:
            children.setdefault(ppid, []).append(pid)
        mine, todo = set(), [os.getpid()]
        while todo:
            p = todo.pop()
            if p not in mine:
                mine.add(p)
                todo += children.get(p, [])
        engine = helper = 0
        for pid, _, rss_kb, comm in procs:
            if 'pc-helper' in os.path.basename(comm):
                helper += rss_kb
            elif pid in mine:
                engine += rss_kb
        self.engine_mb = max(self.engine_mb, engine / 1024)
        self.helper_mb = max(self.helper_mb, helper / 1024)
        self.samples += 1

    def run(self) -> None:
        while not self.stop.is_set():
            self._sample()
            self.stop.wait(self.interval)


def _maxrss_mb() -> float:
    v = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return v / (1024 * 1024) if sys.platform == 'darwin' else v / 1024       # bytes on macOS, KiB on Linux


def run(conn, out_path: str, mode: str = 'per-day', progress=None) -> dict:
    from app import settings
    from app.ai import throttle
    from app.analysis import analyze_collection, analyze_collection_all_at_once
    throttle.reset_totals()
    sampler = RssSampler()
    sampler.start()
    t0 = time.time()
    if mode == 'all-at-once':
        res = analyze_collection_all_at_once(conn, progress)
    else:
        res = analyze_collection(conn, progress)
    wall = time.time() - t0
    sampler.stop.set()
    sampler.join(timeout=5)
    sampler._sample()
    kinds = dict(conn.execute("SELECT kind, COUNT(*) FROM assets WHERE status = 'present' GROUP BY kind").fetchall())
    photos, videos = kinds.get('image', 0), kinds.get('video', 0)
    busy, rested = throttle.TOTALS['busy'], throttle.TOTALS['rested']
    report = {
        'date': datetime.now().isoformat(timespec='seconds'),
        'machine': {'platform': platform.platform(), 'python': platform.python_version(),
                    'cpu_count': os.cpu_count()},
        'mode': mode,
        'share_setting': settings.load().get('ai_gpu_share'),
        'files': photos + videos, 'photos': photos, 'videos': videos,
        'wall_s': round(wall, 2),
        'photos_per_s': round(photos / wall, 3) if wall > 0 else None,
        'stages_s': res.get('timings_s'),
        'first_day_settled_s': (res.get('days') or {}).get('first_settled_s'),
        'days': res.get('days'),
        'peak_rss_mb': {'engine': round(sampler.engine_mb, 1), 'helper': round(sampler.helper_mb, 1),
                        'engine_ru_maxrss': round(_maxrss_mb(), 1), 'samples': sampler.samples},
        'throttle': {'busy_s': round(busy, 2), 'rested_s': round(rested, 2),
                     'share_used': round(busy / (busy + rested), 3) if busy + rested > 0 else None},
        'result': {k: res.get(k) for k in ('duplicate_groups', 'quality', 'faces', 'videos', 'screenshots',
                                          'keepers_changed_after_all_days')},
        'not_measured': ['first photos visible on the Sorting page (app side)', 'grid frame drops',
                         'app memory with 3,000 thumbnails'],
    }
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False, default=str)
    return report

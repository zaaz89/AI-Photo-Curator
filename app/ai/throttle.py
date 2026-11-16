"""Keep long jobs gentle on the Mac (owner's request: no full-load overheating).

macOS cannot cap the GPU share of one process, so long jobs use a duty cycle:
after a step that kept the Mac busy for W seconds, wait W * (100 / share - 1)
seconds. At share 30 the Mac works about 30 % of the time for this app.
Since M11 the owner's share (10-100, a slider) applies to every phase of the analysis
(focus, faces, subject sharpness) and to the search index; parallel work runs in rounds
so the rest after a round really is a rest.
Jobs also pause while macOS reports a thermal or performance warning, and,
if the owner enables it, while the Mac runs on battery.
"""
from __future__ import annotations

import json
import subprocess
import time
from typing import Callable, Iterable, Optional

from app import settings

CHECK_EVERY_S = 30.0


def _pmset(*args) -> str:
    try:
        return subprocess.run(['pmset', '-g', *args], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ''


def on_battery() -> bool:
    return "'Battery Power'" in _pmset('batt')


def thermal_warning() -> bool:
    """True when macOS has recorded a thermal or performance warning level."""
    out = _pmset('therm').lower()
    for line in out.splitlines():
        if 'cpu_speed_limit' in line:
            digits = ''.join(ch for ch in line.split('=')[-1] if ch.isdigit())
            if digits and int(digits) < 100:
                return True
        if 'warning level' in line and 'no ' not in line.split('warning')[0]:
            digits = ''.join(ch for ch in line.split('level')[-1] if ch.isdigit())
            if digits and int(digits) > 0:
                return True
    return False


def pause_reason(cfg: dict) -> Optional[str]:
    if thermal_warning():
        return 'the Mac reports a thermal warning'
    if cfg.get('ai_pause_on_battery') and on_battery():
        return 'the Mac runs on battery'
    return None


# Work and rest of the running job (one analysis runs at a time), for the time estimate.
TOTALS = {'busy': 0.0, 'rested': 0.0}


def reset_totals() -> None:
    TOTALS.update(busy=0.0, rested=0.0)


class Throttle:
    def __init__(self, cancelled: Callable[[], bool] = lambda: False,
                 status: Optional[Callable[[str], None]] = None, share: Optional[int] = None):
        """`share` fixes the duty cycle for this job (tests); by default the owner's setting applies,
        read again after every unit of work."""
        self.fixed_share = share
        self.cancelled = cancelled
        self.status = status or (lambda msg: None)
        self.cfg = settings.load()
        self.last_check = 0.0
        self.mark = time.time()

    @property
    def share(self) -> int:
        return self.fixed_share or int(self.cfg.get('ai_gpu_share', 100))

    def _sleep(self, seconds: float) -> None:
        start = time.time()
        end = start + seconds
        while time.time() < end and not self.cancelled():
            time.sleep(min(0.5, max(0.0, end - time.time())))
        TOTALS['rested'] += time.time() - start

    def after_work(self, busy_s: Optional[float] = None) -> None:
        """Call after each unit of work. Without `busy_s` the time since the previous call (or since the
        throttle was made) counts as work."""
        if busy_s is None:
            busy_s = max(0.0, time.time() - self.mark)
        TOTALS['busy'] += busy_s
        self.cfg = settings.load()                 # the owner may change it mid-job
        if self.share < 100 and busy_s > 0:
            self._sleep(busy_s * (100.0 / self.share - 1.0))
        if time.time() - self.last_check >= CHECK_EVERY_S:
            self.last_check = time.time()
            while not self.cancelled():
                reason = pause_reason(self.cfg)
                if not reason:
                    break
                self.status(f'Paused: {reason}. Resumes by itself.')
                self._sleep(CHECK_EVERY_S)
                self.cfg = settings.load()
        self.mark = time.time()


ROUNDS_AT_FULL_SPEED = 8      # a round at no limit holds this many times the workers' share of items


def throttled_map(fn: Callable, items: Iterable, throttle: Throttle, workers: int = 1,
                  make_pool: Optional[Callable[[int], object]] = None, chunksize: int = 1):
    """Yield (item, result) in order and rest after each round of work by the owner's share.

    One worker: an item is a round. Several: `make_pool(workers)` gives an executor; a round is
    workers x chunksize items (eight times that at no limit, so full speed loses almost nothing),
    and nothing runs while the throttle rests. The last round rests too, so the share holds across
    phases and every round's work is counted for the time estimate."""
    items = list(items)
    if not items:
        return
    pool = make_pool(workers) if workers > 1 and make_pool is not None else None
    try:
        i = 0
        while i < len(items):
            if throttle.cancelled():
                return
            if pool is None:
                batch = items[i:i + 1]
                results = [fn(batch[0])]
            else:
                size = workers * chunksize * (ROUNDS_AT_FULL_SPEED if throttle.share >= 100 else 1)
                batch = items[i:i + size]
                results = list(pool.map(fn, batch, chunksize=chunksize)) if chunksize > 1 \
                    else list(pool.map(fn, batch))
            for it, res in zip(batch, results):
                yield it, res
            i += len(batch)
            throttle.after_work()
    finally:
        if pool is not None:
            pool.shutdown(wait=False, cancel_futures=True)


# Measured speed of this Mac (M11): seconds per photo of a first analysis, split into work the share
# slows down (focus, faces, subject) and the rest (reading files, times, places). local-data/speed.json.
MIN_PHOTOS_FOR_SPEED = 5


def _speed_path():
    from app.collections import data_dir
    return data_dir() / 'speed.json'


def record_speed(photos: int, wall_s: float) -> Optional[dict]:
    """Store the speed of the analysis that just ended (only when it analysed enough new photos)."""
    if photos < MIN_PHOTOS_FOR_SPEED or wall_s <= 0:
        return None
    from app.collections import now_iso
    busy = TOTALS['busy']
    other = max(0.0, wall_s - TOTALS['rested'] - busy)
    out = {'throttled_per_photo': round(busy / photos, 4), 'other_per_photo': round(other / photos, 4),
           'photos': photos, 'measured_at': now_iso()}
    try:
        _speed_path().parent.mkdir(parents=True, exist_ok=True)
        _speed_path().write_text(json.dumps(out, indent=2))
    except OSError:
        return None
    return out


def speed() -> Optional[dict]:
    try:
        d = json.loads(_speed_path().read_text())
        float(d['throttled_per_photo']), float(d['other_per_photo'])
        return d
    except (OSError, ValueError, KeyError, TypeError):
        return None


def estimate_seconds(photos: int, share: int, measured: Optional[dict] = None) -> Optional[float]:
    """First analysis of `photos` photos at `share` %, from the measured speed (None before any measurement)."""
    m = measured if measured is not None else speed()
    if not m or photos <= 0:
        return None
    share = max(1, min(100, int(share)))
    return photos * (float(m['other_per_photo']) + float(m['throttled_per_photo']) * 100.0 / share)

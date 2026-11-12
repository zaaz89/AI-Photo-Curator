"""Keep long AI jobs gentle on the Mac (owner's request: no full-load overheating).

macOS cannot cap the GPU share of one process, so long jobs use a duty cycle:
after a step that kept the GPU busy for W seconds, wait W * (100 / share - 1)
seconds. At share 30 the GPU works about 30 % of the time for this app.
Jobs also pause while macOS reports a thermal or performance warning, and,
if the owner enables it, while the Mac runs on battery.
"""
from __future__ import annotations

import subprocess
import time
from typing import Callable, Optional

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


class Throttle:
    def __init__(self, cancelled: Callable[[], bool] = lambda: False,
                 status: Optional[Callable[[str], None]] = None):
        self.cancelled = cancelled
        self.status = status or (lambda msg: None)
        self.cfg = settings.load()
        self.last_check = 0.0

    @property
    def share(self) -> int:
        return int(self.cfg.get('ai_gpu_share', 100))

    def _sleep(self, seconds: float) -> None:
        end = time.time() + seconds
        while time.time() < end and not self.cancelled():
            time.sleep(min(0.5, max(0.0, end - time.time())))

    def after_work(self, busy_s: float) -> None:
        """Call after each unit of GPU work."""
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

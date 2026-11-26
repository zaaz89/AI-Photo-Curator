"""The analysis as one phase plan (M14c), so the app shows one honest status instead of parsing status text.

Before M14c the job's progress was the share of whatever stage ran last: reading went 0-100 % once per folder,
then clocks 0-100 %, and day 1 showed the 100 % left over from the clocks. The app's toolbar said "Aligning
clocks 100%" while the stage said "Working".

`PhasePlan` follows the pipeline (`app/analysis.py`) and answers one state:

  phase     reading | clocks | places | days | finishing
  step      inside a day: similar | focus | faces | videos | moments (None otherwise)
  day, days the day being sorted (1-based) and how many there are (0 before the per-day loop)
  source_id the folder being read (reading only), source, sources: its index (1-based) and the folder count
  done, total the counter of the current step (0, 0 when it has none)
  progress  0-100, one bar over the whole plan, never goes back

Each phase owns a fixed share of the bar (SPAN); inside the per-day loop every day owns an equal part and every
step of a day a fixed part of that (DAY_STEPS). Pure bookkeeping: no I/O, so it is unit-tested.
"""
from __future__ import annotations

from typing import Optional

PHASES = ('reading', 'clocks', 'places', 'days', 'finishing')
SPAN = {'reading': (0.0, 0.20), 'clocks': (0.20, 0.25), 'places': (0.25, 0.30), 'days': (0.30, 0.97),
        'finishing': (0.97, 1.0)}
# Message keyword (lower case) -> (step, start, end) as parts of one day.
DAY_STEPS = (
    ('visual signatures', 'similar', 0.0, 0.2),
    ('focus and ranking', 'focus', 0.2, 0.45),
    ('subject sharpness', 'faces', 0.45, 0.55),
    ('faces', 'faces', 0.55, 0.8),
    ('videos', 'videos', 0.8, 0.9),
    ('near duplicates', 'moments', 0.9, 1.0),
    ('moments', 'moments', 0.9, 1.0),
)


class PhasePlan:
    def __init__(self, sources: int = 1):
        self.phase = 'reading'
        self.step: Optional[str] = None
        self.day = 0
        self.days = 0
        self.source = 0
        self.sources = max(1, int(sources or 1))
        self.source_id: Optional[int] = None
        self.done = 0
        self.total = 0
        self._frac = 0.0                 # inside the current phase (0-1)
        self._progress = 0.0

    # ---- transitions (called by the pipeline) ----------------------------------------------------------------

    def enter(self, phase: str) -> None:
        if phase not in SPAN:
            raise ValueError(phase)
        if PHASES.index(phase) < PHASES.index(self.phase):
            return                       # phases only move forward
        if phase != self.phase:
            self.phase, self.step, self._frac, self.done, self.total = phase, None, 0.0, 0, 0
            if phase != 'reading':
                self.source_id = None
        self._advance()

    def start_source(self, index: int, count: int, source_id: int) -> None:
        """Reading folder `index` (0-based) of `count`."""
        self.enter('reading')
        self.sources = max(1, count)
        self.source = index + 1
        self.source_id = source_id
        self.done = self.total = 0
        self._frac = index / self.sources
        self._advance()

    def start_day(self, index: int, count: int) -> None:
        """Sorting day `index` (0-based) of `count`."""
        self.enter('days')
        self.days = max(1, count)
        self.day = index + 1
        self.step, self.done, self.total = None, 0, 0
        self._frac = index / self.days
        self._advance()

    def day_done(self, index: int) -> None:
        self._frac = max(self._frac, (index + 1) / max(1, self.days))
        self._advance()

    # ---- progress messages (the pipeline's `progress(msg, i, n)`) --------------------------------------------

    def update(self, msg: str, i: int = 0, n: int = 0) -> None:
        part = (i / n) if n else 0.0
        part = min(1.0, max(0.0, part))
        if n:
            self.done, self.total = int(i), int(n)
        if self.phase == 'reading':
            if n:
                self._frac = max(self._frac, (max(0, self.source - 1) + part) / self.sources)
        elif self.phase == 'days' and self.day:
            low = msg.lower()
            for key, step, a, b in DAY_STEPS:
                if key in low:
                    if step != self.step:
                        self.step = step
                        if not n:
                            self.done = self.total = 0
                    self._frac = max(self._frac, (self.day - 1 + a + (b - a) * part) / self.days)
                    break
        elif n:
            self._frac = max(self._frac, part)
        self._advance()

    def _advance(self) -> None:
        a, b = SPAN[self.phase]
        self._progress = max(self._progress, a + (b - a) * min(1.0, self._frac))

    def finish(self) -> None:
        self.enter('finishing')
        self._frac = 1.0
        self._advance()

    # ---- the answer --------------------------------------------------------------------------------------------

    @property
    def progress(self) -> int:
        return int(round(self._progress * 100))

    def state(self) -> dict:
        return {'phase': self.phase, 'step': self.step, 'day': self.day, 'days': self.days,
                'source': self.source, 'sources': self.sources, 'source_id': self.source_id,
                'done': self.done, 'total': self.total, 'progress': self.progress}

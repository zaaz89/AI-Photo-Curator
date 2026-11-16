# M11: settings in the app

Owner, 2026-11-16: "I must be able to change the GPU from 30 % to more; I want smart settings in the app."
Chosen from the proposals: a slider 10-100 % that applies to all work; settings visible in the app with a
sentence per setting and a time estimate; strictness of the quality check. Not chosen: keeper profiles, export defaults.

## Engine

- `ai_gpu_share` accepts any whole number 10-100 (`settings.RANGES`), was 25 / 30 / 50 / 100.
- The share applies to every phase again (focus, faces, subject sharpness, search index). Until now the
  M9 speed-up had taken focus and faces out of the duty cycle, so the setting only slowed the search index.
  `throttle.throttled_map` runs parallel work in rounds (workers x chunk items; 8 x that at 100 %) and rests
  after each round by the measured work time, so the rest is real: no worker runs while the throttle rests.
- Speed of this Mac: the analysis job counts work inside throttled phases and the rest, and stores seconds
  per photo in `local-data/speed.json` (only after at least 5 new photos). `GET /api/settings` returns it as
  `speed`; the app computes the estimate for the album's photo count (`EngineSpeed.seconds`, same formula as
  `throttle.estimate_seconds`).
- `quality_strictness`: lenient | normal | strict (`app/quality/strictness.py`). Normal is the calibrated
  behaviour. Lenient and strict move the blur lines (x 0.75 / x 1.3) and the closed-eye lines (shut below
  0.09 / 0.15; closed within a moment at 55 % / 75 % of the face's best, below 0.16 / 0.24). All verdicts are
  made when results are read, so a change applies to every album at once.

## App

- `Destination.settings`: a page in the main window (sidebar button above Finish Album, a line on the album
  home with "Change"), the same page in the Settings window (⌘,), and `photocurator://go?page=settings`.
- Sections: analysis speed (slider, what it applies to, estimate, battery pause, thermal note), quality
  check (three levels, a sentence per level, blurry count in this album now), best of each moment
  (weights), language.

## Checked

- test-10 in a throwaway data folder: 13.9 s at 100 %, 31.7 s at 30 %; the estimate from the 100 % run for
  30 % was 28 s. Test photos byte-identical.
- The owner's album "Tuscany" (255 analysed photos), read only: lenient 0 blurry / 2 soft / 0 photos with
  closed eyes; normal 1 / 4 / 3 (same as the calibration); strict 2 / 17 / 3.

## Not verified

- Lenient and strict are not calibrated on their own; the strict "soft" photos were not looked at one by one.
- The estimate assumes the album is like the one measured (videos, RAW and phone HEIC differ in speed).

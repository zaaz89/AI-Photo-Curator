# M13: scale (3,000 files, live per-day pipeline)

**Status:** built 2026-11-26 by Claude (Cowork) on `claude/m13-scale` (base: M12f, PR #19). Python tested on Linux;
Swift NOT compiled; the benchmark NOT run on real photos. Roadmap: `notes/m13-m18-roadmap.md` → M13.

## 1. Budgets (acceptance targets)

At 30 % analysis share on the M5 Pro, on `local-data/bench/bench-3000` (section 4):

| Measure | Target | Measured by |
|---|---|---|
| First photos visible on the Sorting page after adding sources | < 5 s | by hand (screen capture with time stamps); not in the bench JSON |
| Day 1 fully sorted (moments, verdicts) | < 2 min for ~400 photos | bench `first_day_settled_s` (+ index/clocks time before the loop) |
| Whole 3,000-file album | < 25 min at 30 % | bench `wall_s` |
| Engine peak memory | < 2.5 GB | bench `peak_rss_mb.engine` (engine + its process pool), `.helper` separately |
| App memory with 3,000 thumbnails | < 1 GB | Activity Monitor / `footprint` on the app after scrolling the 3,000-photo stage grid |
| Grid scroll at 3,000 photos | no visible dropped frames in a 10 s window capture (Instruments if available) | by hand |

If a budget is missed: fix the largest stage first (`stages_s` in the bench JSON) and record before/after numbers
in `project-log.md`.

## 2. Per-day pipeline (13.3)

`app/analysis.py` → `analyze_collection`:

1. index all files (cheap) → screenshots → clocks → places and timeline events (all files, once);
2. `read` events for every new photo (time order);
3. day by day, chronologically ("unknown" last): visual signatures → focus/ranking → faces (Apple Vision) +
   subject sharpness → videos → moments (`build_groups(conn, day=…)`), each stage limited to that day's photos
   (`shas=`). A day is **settled** when its moments exist: the photos of the day get `scored` / `removed` /
   `stacked` events, then one `settled_day`, and `analysis_days` stores the day with a signature of its
   (asset id, sha256, corrected time);
4. after the last day: `refresh_keepers` chooses every keeper again without comparing photos (focus verdicts are
   relative to the whole album's median, so an early day's best frame can change once later days are in), and
   every photo whose place changed gets a new event.

Rules:
- **Clocks** are synced once from the metadata of all files before the loop, so a later day never moves an earlier
  one. An owner's clock change (`POST …/clocks/<id>`) calls `rebuild_changed_days`: only days whose signature
  changed (photos moved in or out, times shifted) get their moments rebuilt; the rest stay. Albums analysed before
  M13 (no `analysis_days`) get the old whole-album rebuild.
- **Moments never span two days** (owner-visible decision, also in the brief §5.2). The old whole-album order is
  kept as `analyze_collection_all_at_once` for tests and the bench; on the fixture both give the same moments,
  keepers, reasons and verdicts (`tests/test_m13_scale.py`).
- **Cancel / resume** at day granularity: a stopped day is not settled (a cancelled `build_groups(day=…)` stores
  nothing). The next run skips settled days whose signature still matches and where the stages found nothing new;
  it resumes at the first unsettled day. Stages skip what is already measured, as before.
- **Keeper choice** (`POST …/duplicates/<id>/keeper`) now only re-chooses keepers (`after_owner_change`), no ORB.
- **Throttle**: unchanged. Every stage still makes its own `Throttle` (share, thermal and battery pauses); the
  totals add up over all days. The job's progress bar shows the share of days done once the loop starts.
- Cost of going per day: each stage queries the album once per day (cheap) and the process pools (quality,
  subject) start once per day instead of once (about a second each on macOS spawn; measure in the bench).

## 3. Event stream

`GET /api/collections/<id>/events?since=N&limit=500` (limit ≤ 2000) →
`{events: [{seq, asset_id, kind, reason?, keeper_id?, day}], next, more, latest}`, oldest first.

| kind | meaning |
|---|---|
| `read` | indexed; the tile can fly in |
| `scored` | results in, stays in the album |
| `removed` | leaves the album; `reason`: `screenshot`, `leftOut`, `movement_blur`, `subject_blurry`, `whole_blurry` |
| `stacked` | another frame of a moment; `keeper_id` |
| `settled_day` | the day's places are final (`asset_id` null) |

An asset gets an event only when its place changes, so the newest event per asset is its current place (same rule
as the app's `sortVerdict` and the export, `app/analysis_events.places`). Table `analysis_events` (migration 13,
`seq` AUTOINCREMENT, never reused) and `analysis_days`. Pruned on "Finish album" (`prune`, then the database is
deleted anyway). Marks set from the grid do not write events (the app already knows them); keeper choices and clock
changes do.

App side (13.4): `CuratorCore/AnalysisEvents.swift` (`AnalysisEvent`, `AnalysisEventPage`, `SortStream.merge`,
`eventPollInterval`, `shouldReloadPhotos`, `stageDaysText`), `APIClient.analysisEvents`. `LibraryModel.pollEvents`
runs only while this album's analysis runs (0.7 s, up to 4 pages per poll) and once when it ends; it reloads the
photos when a day settled, or at most every 2 s when photos were judged. The Sorting stage reveals verdicts and
stacks frames for **settled days** while later days are still read (an engine without the stream: as before, after
all photos have results). Above 400 photos (`stageChoreographyLimit`) the stage snaps: the lazy grid updates per day
without per-photo animation. Header subtitle: "Album · 2 of 7 days sorted".

Thumbnails: `ThumbnailCache` keeps its concurrency limit and stand-ins, but is now a `ByteLRU` (CuratorCore,
O(1) least-recently-used, bounded by bitmap bytes, `thumbnailCacheBudgetBytes` = 384 MB) instead of an `NSCache`
with a 3,000 count limit (3,000 × 520 px would be ~3 GB). Quick Look decodes off the main thread at the bucket
size; the stage grid asks for 150 pt (new 160 bucket, 320 px at 2x, ~400 KB each).

## 4. Benchmark (13.1): how to run

Ask the owner first (long AI job rule). Then, on the Mac:

```bash
uv run python scripts/make-bench-set.py            # test-photos/test-10 -> local-data/bench/bench-3000 (deterministic, --seed 13)
scripts/bench.sh --share 30 --yes                  # per-day pipeline at 30 %
scripts/bench.sh --share 100 --yes                 # and at 100 %
scripts/bench.sh --share 30 --mode all-at-once --yes   # the pre-M13 order, for comparison
```

- The set: 3 sources (`cam-a`, `cam-b`, `phone-c`), 7 days, 8 % near-duplicate bursts (2-4 frames 0.5 s apart),
  5 % blurry, 2 % screenshots (PNG, no camera EXIF), 60 videos (3 s clips from stills via ffmpeg; skipped with a
  note when ffmpeg is missing), the rest distinct crops (30-60 % of a test photo, mirror, channel order, exposure,
  JPEG 70-95). Variants are new files at 3,000 px long side (`--max-side`); about 2 MB each, ~6 GB in total.
  Originals are only read. Variants keep the EXIF of the photo they came from; `bench-times.json` spreads them over
  7 days and is read by the indexer only when `PHOTOCURATOR_BENCH_TIMES` is set and only for files inside the
  bench folder (`app/importers/local_importer.bench_time_shifts`).
- `bench.sh` makes a fresh data folder per run (`local-data/bench/data-<stamp>`, links `bin`, `geo`, `models`),
  writes the share into its settings, creates the album through `app.cli`, adds the three sources and runs
  `app.cli bench`. Output: `local-data/bench/results-<stamp>-<mode>-share<N>.json` (wall time, per-stage times,
  `first_day_settled_s`, peak RSS of engine and helper sampled with `ps` every 0.5 s plus `ru_maxrss`, photos/s,
  throttle busy/rested and the share really used) and `run-<stamp>.log` (progress).
- Sets over 200 files need `--yes`.

## 5. What was verified, what was not

- Python: `uv run pytest` 163 passed on Linux (157 before + 6 in `tests/test_m13_scale.py`: per-day equals
  all-at-once, events ordered/complete, resume after cancel identical, clock change rebuilds only affected days,
  endpoint pagination, bench time shift only inside the bench folder). ExifTool installed in the container.
- Bench scripts: smoke-tested only, on 4 generated JPEGs → a 30-file set (28 photos, 2 videos via ffmpeg, 8 days
  incl. one undated screenshot), both modes, Linux, no helper. Generation is byte-identical for the same seed.
  These numbers say nothing about the Mac.
- NOT measured: every budget in section 1; real test-10 or the 3,000-file set; the helper (faces, videos) inside
  the per-day loop; process-pool start cost per day on macOS; app memory, first-photo latency, grid frame rate.
- NOT compiled: all Swift (Linux container). Swift Testing tests written in
  `mac/Tests/CuratorCoreTests/AnalysisEventsTests.swift` (event decoding, merge, reset, pacing, ByteLRU, buckets).

# M2: device clocks and duplicates

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** sections 4.3 (clock synchronization) and 5 (duplicate detection).

## Pipeline

`app/analysis.py` runs, in one job: index → capture times → relationships → clocks → visual signatures → duplicate groups. The `/timeline` page's "Index photos" button and `app.cli index` both run it.

## Device clocks (`app/timeline/clock_sync.py`)

A clock is one device in one source (source + make + model). The clock with the most dated photos is the reference.

Evidence, in order:

1. **GPS.** Camera time vs GPS UTC time in the same files. Median of at least 3 photos; spread over 30 s means "conflicting".
2. **Scene matches.** For every photo of the other clock, the best reference photo within ±20 min (up to 40 candidates) by ORB + RANSAC fundamental-matrix inliers (at least 40). Matches are made independent: one per 10 s of shooting, one per reference photo. Deltas are clustered with ±10 s tolerance.

A suggestion needs at least 3 independent matches that agree, and no competing cluster of half that size. High confidence needs 5 or more matches and a competing cluster of at most a third. Anything else is shown as "not enough evidence" or "conflicting", with the numbers. Suggestions are never applied automatically. The owner can apply them, set a manual value (at most ±48 h), reject them or undo. `capture_time` keeps the file's values; the timeline shows corrected and original side by side.

Known limit: the same physical camera split over two sources is two clocks. Lightroom exports drop the body serial number, so they cannot be joined automatically.

## Duplicates (`app/duplicates/`)

- `visual_features` caches a 192-bit signature (aHash + dHash h/v, EXIF orientation applied) and sharpness per SHA-256.
- Edges: identical SHA-256 → exact. Signature ≥ 0.92 → near. Signature ≥ 0.85 within 3 s on the same clock → near (burst). Signature ≥ 0.80 → ORB check: confirmed means near, otherwise similar scene.
- Long chains are split: walking a group in time order, a frame that no longer resembles the first frame of its subgroup (< 0.80) starts a new subgroup.
- The keeper is recommended by 0.7 × sharpness + 0.3 × resolution, with reasons. The owner's choice is stored by content (`keeper_choices`) and survives re-analysis. Similar-scene groups have no keeper: keep both.
- Nothing is moved, hidden or deleted. The timeline marks non-keepers with a "duplicate" flag.

## Bug found and fixed

`cv2.findFundamentalMat` returns `F=None` and a mask with undefined content (values up to 254) when it finds no model. Summing that mask produced 13,370 "inliers" for two unrelated test images and a false clock match. Inliers now count only when a model exists.

## Verified

- 42 pytest tests, stable over 3 runs. New: consistent offset → high-confidence suggestion of −50 s, never auto-applied; apply reorders the timeline and undo restores it; conflicting clusters → no suggestion; 1 match → no suggestion and accept refused; GPS-derived −30 s; manual limits; exact + burst groups, unrelated photo not grouped; keeper choice survives re-analysis; API errors. Every analysis test checks the source folders stay byte-identical.
- Real set `~/Desktop/photos` (236 JPEGs): full analysis 40 s the first time, 22 s with cached signatures. A7 III vs A7 IV: 2 independent scene matches pointing to −52 s and −17 s, so no suggestion. Palazzo folder: 0 matches. 25 near-duplicate groups (largest 4 frames) and 4 similar-scene groups. Source files unchanged.
- In the browser: clock panel, manual −45 s applied and undone, Duplicates tab with keeper and reasons.

## Not verified

- Whether the 25 near-duplicate groups match what a person would group. That needs the owner's review of the Duplicates tab.
- Real phones with GPS, HEIC and Live Photos (none in the test set).
- Large collections: the signature comparison is O(n²) in blocks of 1,000 and the ORB checks are bounded by time windows, but nothing has been timed above 236 files.

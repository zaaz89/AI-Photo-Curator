# M1: multi-source indexing and timeline

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** section 22 milestone. Done when two folders from different devices import and show one correctly ordered timeline with confidence and provenance.

## What exists

| Module | Job |
|---|---|
| `app/database/db.py` | SQLite schema, migrations via `PRAGMA user_version` |
| `app/collections.py` | Create and list collections (`local-data/collections/<slug>/curator.db`), add sources |
| `app/importers/local_importer.py` | Recursive read-only scan, SHA-256, incremental re-index, missing files, relationships |
| `app/metadata/exif_reader.py` | ExifTool batch reader (JSON, `-n -G0`), Pillow fallback |
| `app/metadata/timestamp_resolver.py` | Capture time rules, confidence, notes |
| `app/timeline/timeline_engine.py` | Ordered timeline plus summary |
| `app/web/timeline_bp.py`, `templates/timeline.html` | API and the `/timeline` page |
| `app/cli.py` | `create`, `add-source`, `index`, `timeline`, `list` |

## Data model

- `metadata_raw` keeps ExifTool's original output per file, untouched.
- `capture_time` is derived: local time, UTC, offset, rule, confidence, notes, sort key. It is recomputed from `metadata_raw` after every index, so new rules apply without re-reading files.
- `assets.status` is `present` or `missing`. Files deleted from a source stay in the index as `missing`.
- `relationships` records `raw_jpeg`, `live_photo` (same `ContentIdentifier`) and `live_photo_candidate` (same name, no identifier). Nothing is hidden or dropped because of a pair.

## Capture time rules

The rules are listed in the docstring of `timestamp_resolver.py`. Two behaviours worth knowing:

- An assumed offset comes from the most common explicit offset among the same source's files. A source that spans two time zones gets the wrong assumption for the minority. Those files are marked `medium` with the reason in the notes.
- Without any offset the timeline orders by the recorded wall clock and marks the file `low`. Mixing such a source with one that has offsets can misorder by the zone difference. Clock offset correction is M2.

EXIF `ModifyDate` (export or edit time) is never used.

## Verified

- 34 pytest tests, including two synthetic phones with colliding names, GPS-derived offset, assumed offset, no metadata, an exact copy, hidden files, a DST change, incremental re-index, missing files, RAW+JPEG and Live Photo pairing, the HTTP API and thumbnails. Every indexing test checks that the source folders are byte-identical afterwards.
- Real set `~/Desktop/photos` (236 Lightroom JPEGs, two Sony cameras): indexed in about 4 s, all 236 `high` (`DateTimeOriginal` + `OffsetTimeOriginal` +02:00). The second run skips all 236. Source files unchanged (SHA-256, size, mtime).
- `/timeline` page checked in a browser on the real set: grid by day and hour, source colours, detail panel with rule and notes.

## Not covered yet

- Real HEIC, Live Photo and video files. Rules and pairing are tested with metadata as ExifTool reports it, not with real iPhone files.
- Google Takeout JSON sidecars.
- Clock drift between devices (the two Sony cameras may disagree by seconds or minutes). That is M2.
- Video thumbnails (the page shows a placeholder).
- The timeline renders every item at once. Fine for thousands; tens of thousands will need paging.

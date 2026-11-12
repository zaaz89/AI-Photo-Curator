# Phase 0 audit

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Scope:** brief section 22, tasks 1–9. Task 10 (first milestone) is not implemented yet.  
**Code audited:** upstream v7.0, commit `1cb56a0`.

Every claim below is either taken from the code (with `file:line`) or from the baseline probe described in section 2. Anything not verified says so.

## 1. Summary

The upstream app is a working single-folder culling tool: cull by sharpness, dedup by perceptual hash, rank by a weighted score. Its loopback and path-traversal protections work as documented. It is not safe for this project's workflow as it is: three code paths move original photos, analysis writes files into the source folder, the "dry run" creates folders, and exports land inside the source folder.

Capture time is read wrongly. Both the EXIF panel and the dedup burst logic prefer the IFD0 `DateTime` tag (last edit or save time) over `DateTimeOriginal` (capture time). Time zones, sub-seconds and GPS time are ignored, and photos are sorted by filename. The core requirement of this project, one correct timeline from two phones, needs new code rather than a fix to existing code.

Recommendation: keep the existing analysis code (sharpness, perceptual hash, ORB, ranking, RAW/HEIC loading) and the Flask UI. Build the new indexing, metadata and timeline layer as a separate `app/` package with SQLite. Before that, make one small safety PR so the existing app can be run on real photos without risk.

## 2. How this was checked

- Read all Python modules. The safety-relevant paths were read in full, and a sub-agent mapped the rest. Its claims used below were spot-checked against the code.
- Installed `requirements.txt` in a virtualenv on Python 3.9.6 (macOS system Python) and on Python 3.12.13 (via `uv`). Both import and run on Apple M5 Pro, macOS 27.2.1, arm64.
- Ran `pip-audit -r requirements.txt`.
- Ran a baseline probe against four synthetic JPEGs with known EXIF: `DateTimeOriginal` 18:14:32, `OffsetTimeOriginal` +02:00, IFD0 `DateTime` 20:00:00. The probe drove the real Flask app through its test client (cull, dedup with auto-move, rank, export) and diffed the source folder before and after. The probe script is not committed. It becomes the first regression test in milestone M0.

Probe results:

| Check | Result |
|---|---|
| Capture time used by dedup | 20:00:00 (IFD0 `DateTime`), not 18:14:32 |
| Capture time shown by `/api/exif` | 20:00:00, not 18:14:32 |
| `PhotoOrganizer.preview_moves` (dry run) | created `Blurred/`, `Duplicates/`, `TOP_1/` |
| Dedup with auto-move on | moved 2 originals out of the folder into `Duplicates/` |
| Files created in the source folder | `.dedup_sig_cache.json`, `Duplicates/…`, `TOP_2/…` |
| Request with foreign `Host` | 403 |
| Cross-origin POST | 403 |
| `../../etc/passwd` via `/api/image` | 404 |

The probe used random-noise images. Dedup grouped two different noise images together. That says nothing about real photos, because noise collapses to similar 8×8 hashes. Duplicate accuracy has to be measured on a real labeled set (brief section 20).

## 3. Risks to source photos

Ordered by severity.

1. **Originals are moved on a status click.** `api_toggle_status` (`photo_curator.py:2122`) calls `_relocate_for_status` (`:672-706`). It runs `shutil.move` on the original into or out of `Blurred/` whenever `Blurred/` exists or auto-cull is on. It finds the file by name (`folder/name`, `Blurred/name`), not by identity.
2. **Dedup auto-move.** When the "Auto-move duplicates" checkbox is on, `run_dedup` moves every non-keeper original into `Duplicates/` (`:823-830` → `photo_file_organizer.py:77-119`). Confirmed by the probe.
3. **Move blurry.** `/api/move-blurry` (`:2155`) moves originals into `Blurred/`. It asks for confirmation in the UI, but it still moves originals.
4. **Overwrite on name collision.** The move helpers rename on collision with a one-second timestamp suffix (`photo_file_organizer.py:58-59`, `photo_curator.py:699-700`). `shutil.move` onto an existing path overwrites it on macOS. Two collisions within the same second would lose a file. Unlikely, not observed.
5. **The dry run is not dry.** `preview_moves` (`photo_file_organizer.py:159-169`) calls `_ensure_dir` before checking `dry_run`. If an exception occurs, `dry_run` stays `True` for that instance. The method is currently unused by the app.
6. **Analysis writes into the source folder.** The dedup signature cache is written to `<photo folder>/.dedup_sig_cache.json` (`photo_curator.py:752`). On a Google Drive synced folder this file would sync to the cloud.
7. **Exports go inside the source folder.** `TOP_N/` (`:2184`) and `PhoneBG/` (`:2260`) are created inside the photo folder. `copy2` overwrites earlier exports with the same name and does no checksum verification. There is no manifest.
8. **Folder taken from the request body.** `api_run` (`:2040-2044`) accepts any `folder` from the JSON body, makes it the current folder and adds it to "recents". Recents widen the read whitelist for `/api/image`. Only same-origin requests reach it, so the risk is low. It still means the whitelist is "every folder ever used".

## 4. Architecture findings

- **One 2,289-line file.** `photo_curator.py` holds the routes, analysis loops, EXIF parsing, thumbnailing and the whole HTML/CSS/JS UI as one string (about lines 953–1840).
- **Global mutable state without locks.** A single `state` dict is shared by request threads and worker threads. `api_run` does not check whether a step is already running, so two threads can write the same step's results.
- **Nothing persists.** Cull, dedup and rank results live in memory and are lost on restart. Thumbnails go to `/tmp/photocurator_thumbs` (`:134`), keyed by path+mtime and never pruned.
- **Single folder, non-recursive, filename order.** `list_images` (`:269-278`) reads one folder level and sorts by filename. iPhone exports and Google Drive folders usually have subfolders, and filenames from two phones (`IMG_1234.HEIC`) collide and interleave meaninglessly.
- **No source identity.** There is no notion of owner, device or import source. Paths are the only identity.
- **Dead code.** `photo_ranking_engine.py` is not imported anywhere. `PhotoOrganizer.copy_top_photos`/`preview_moves` and three `FastBatchDeduplicator` methods (`deduplicate_all`, `deduplicate_batch`, `cluster_similar_photos`) are unused.
- **Docs drift.** The module docstring says "v3, port 5001" (the real default is 5014). The dedup keeper is chosen by whole-frame sharpness only (`photo_curator.py` `_LiteScore`), not by the rank score the docs describe. `READ ME.txt` refers to a `Start Photo Curator.command` launcher that is not in the repo.
- **No tests.**

## 5. Metadata and timeline gaps

| Need (brief §4.2) | Upstream |
|---|---|
| `DateTimeOriginal` from the Exif IFD | read only if IFD0 has no date (`photo_curator.py:1963-1982`); the dedup engine never reads the Exif IFD (`photo_dedup_batch.py:183-207`) |
| `SubSecTimeOriginal`, `OffsetTimeOriginal` | not read |
| GPS date/time | not read |
| QuickTime / video dates | videos are not supported |
| Normalized UTC time + confidence + provenance | none; naive local strings |
| Sort by capture time | sort by filename |
| Live Photo pairing | none (HEIC only, the `.MOV` part is ignored) |
| RAW+JPEG pairing | yes, by stem (`collapse_raw_jpg_pairs`) |
| GPS | lat/lon only, 6 decimals; no altitude or time |

Pillow alone cannot read QuickTime metadata or Apple's Live Photo `ContentIdentifier`. ExifTool reads all of these, from images and videos, in one batch call with JSON output. It is not installed on this Mac (`brew install exiftool`).

## 6. macOS and Apple Silicon compatibility

- Runs natively on arm64 with the pinned wheels on Python 3.9 and 3.12. No Rosetta needed.
- Python 3.9 is end-of-life since October 2025, and the macOS system Python is 3.9.6. The pinned Pillow fixes need Pillow 12+, which no longer supports 3.9. Recommendation: Python 3.12 managed by `uv`, with a project `pyproject.toml`.
- OpenCV is the headless build, so it has no GUI or Qt dependencies.
- Native folder picker: `native_folder_dialog` (`:459`) uses AppleScript via `osascript`. Fine for a personal tool.
- Not available yet and needed later: ExifTool (phase 1), Ollama (phase 3).

## 7. Dependency health and security

`pip-audit` on the pinned set, 2026-11-12:

| Package | Pinned | Known advisories | Fixed in |
|---|---|---|---|
| Pillow | 11.3.0 | 57 | 12.1.1 – 13.0.0 |
| Werkzeug | 3.1.8 | 1 | 3.1.9 |
| pillow-heif | 1.1.1 | 1 | 1.3.0 |

Pillow decodes every photo the app opens, so its advisories are the relevant attack surface. The realistic attacker is a crafted image in a shared folder. Upgrade in M0. numpy 1.26 and OpenCV 4.10 have no listed advisories but are a major version behind. Upgrade them only together with tests.

Outbound network requests, all made by the browser:
- **OpenFreeMap tiles** for the GPS map. The tile requests reveal the approximate locations being viewed to a third party. The brief asks for local-first, so keep the map opt-in or show a notice.
- **Ko-fi badge** image (`photo_curator.py:1102`). Remove it in the fork.

The loopback binding (`:2289`), Host/Origin guard (`:65-80`) and realpath whitelist (`:170-193`) work as described in `SECURITY.md` (probe results above). One gap: `SECURITY.md` mentions a Referer check that the code does not do. That matters little, because browsers send `Origin` on cross-site POSTs.

## 8. Target architecture

The brief's section 13.3 structure is right. Two additions:

- **App data outside source folders.** Each collection lives in `local-data/collections/<id>/` inside the project folder (ignored by git; owner's decision 2026-11-12), with `curator.db` (SQLite), `thumbs/` and caches. Nothing is written to source folders, ever. Exports go to a destination the user picks, which must not be inside any source.
- **Read-only source access by construction.** Importers and analyzers receive source paths through one `SourceReader` that opens files read-only and has no write methods. Only `organization/export_engine.py` writes, and only to the export destination, after a manifest is generated.

How old and new code connect:

```text
photo_curator.py (existing Flask app, UI)
  ├─ existing routes: cull / dedup / rank (made non-destructive in M0)
  └─ new blueprint: /collections, /timeline  ──►  app/ package
                                                  ├─ database/      SQLite schema + migrations
                                                  ├─ importers/     local_importer (recursive, read-only)
                                                  ├─ metadata/      exif_reader (ExifTool batch, Pillow fallback)
                                                  │                 timestamp_resolver, gps_resolver
                                                  ├─ timeline/      timeline_engine (later clock_sync, events)
                                                  ├─ duplicates/    existing hash + ORB moved here (M2)
                                                  └─ safety/        source_reader, operation_manifest
```

The existing `raw_loader.py`, `photo_dedup_batch.py` and `photo_ranking_v3.py` move into `app/` only when a milestone touches them, with thin re-export shims so `photo_curator.py` keeps working.

**Timestamp resolver, proposed rules** (to be confirmed with tests):

1. `DateTimeOriginal` + `SubSecTimeOriginal` + `OffsetTimeOriginal` → UTC, confidence `high`.
2. `DateTimeOriginal` without offset, but GPS date/time present → offset derived from GPS time, confidence `high` if consistent within 2 s, else `medium`.
3. `DateTimeOriginal` without offset or GPS → local time with the collection's assumed time zone, confidence `medium`, flagged "time zone assumed".
4. QuickTime `CreationDate` (with offset) for videos → `high`; `CreateDate` (UTC by spec, often wrong) → `medium`.
5. Google Takeout sidecar `photoTakenTime` → `medium`.
6. Filename pattern (`IMG_20261023_181432`) → `low`.
7. Filesystem times → `unknown`, never used for ordering ahead of anything above. Shown as uncertain.

Every resolved time stores the original raw values, the rule used and the assumption made.

## 9. Prioritized implementation plan

### M0: Safety lock (small PR, before running on real photos)

- Python 3.12 via `uv` and `pyproject.toml`. Bump Pillow, Werkzeug and pillow-heif to fixed versions.
- Remove the three move paths: tier changes become marks only, auto-move and "Move blurry" go away.
- Move the dedup cache and thumbnails to the app data folder.
- Exports go to a user-chosen destination outside the source, with collision-safe names, SHA-256 verification and a manifest.
- Fix the EXIF date precedence: `DateTimeOriginal` from the Exif IFD first, in both the EXIF panel and dedup.
- Guard against double-starting a step, and add a lock around `state`.
- Remove the Ko-fi badge.
- `pytest` setup. The baseline probe becomes a test that asserts the source folder is byte-identical after every workflow.

Done when: a full cull → dedup → rank → export run leaves every source folder byte-identical (checked by test), and `pip-audit` is clean.

### M1: Multi-source indexing and timeline (brief's first milestone)

- `app/` package with SQLite schema: collections, sources (folder, owner, device), media_assets (path, sha256, size, mtime), metadata_raw, metadata_resolved, asset_relationships.
- Recursive read-only importer with incremental re-scan (skip by size+mtime, confirm by hash).
- ExifTool batch reader, falling back to Pillow when ExifTool is missing.
- Timestamp resolver as in section 8, with confidence and provenance.
- Live Photo pairing (`ContentIdentifier`) and RAW+JPEG pairing as relationships. Nothing is hidden or dropped.
- Read-only `/timeline` page: all sources interleaved by resolved UTC time, colored by owner, uncertain times marked.
- Tests on generated fixtures: two "phones", colliding filenames, missing EXIF, different offsets, a DST transition, a Live Photo pair.

Done when: two folders from two phones import, and the timeline orders them correctly with confidence and provenance shown (brief section 22).

### M2: Clock offset and duplicates on the index

Exact duplicates by SHA-256. The existing hash + ORB moves into `app/duplicates/` and runs on the index. The four categories from brief §5.3 apply. Per-source clock offset suggestions from matched pairs (≥3 independent matches) are stored as reversible corrections.

### M3 and later

Follow the brief: AI understanding (embeddings first, VLM only on selected photos), events, smart export, UI.

## 10. Open questions for the owner

1. Install ExifTool with Homebrew? It is the only practical way to read video and Live Photo metadata.
2. Store collections in `~/Library/Application Support/AI Photo Curator/`?
3. Remove the move features from the fork entirely (recommended), or keep them behind a confirmation?
4. A small real test set: 50–100 photos and a few videos from both phones of one trip, in `local-data/` (never committed). Synthetic fixtures cannot validate time zones, Live Photos or duplicate accuracy.
5. Which agent does M0 and which does M1? M0 and M1 touch different files, so they can run in parallel. M1's tests are more reliable on top of M0's Python 3.12 setup.

### Owner's answers (2026-11-12)

1. ExifTool: yes. Installed with Homebrew, version 13.55.
2. App data: inside the project folder, in `local-data/` (ignored by git), not in `~/Library`.
3. Move features: remove them from the fork entirely.
4. Real test set: `~/Desktop/photos`, read-only. Contents checked with ExifTool: 236 JPEGs (2.5 GB) in two subfolders, `Engagement` (212) and `Palazzo Piccolomini` (24). Two cameras: Sony ILCE-7M4 (210) and ILCE-7M3 (26). All are Lightroom Classic exports. All have `DateTimeOriginal` and `OffsetTimeOriginal` +02:00, none have GPS. Capture times are 2026-10-23, 17:46–18:40. This set is good for testing two devices at one event and the date precedence bug. It does not cover iPhone HEIC, Live Photos, videos, GPS or time zone changes, so synthetic fixtures still cover those.
5. Open.

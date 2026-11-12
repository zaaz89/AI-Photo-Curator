# M5: smart export

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Brief:** sections 8 (smart file naming), 9 (folder organization), 16 (file safety), phase 5.

## What it does

`app/organization/export_plan.py` builds a plan (original path → new relative path) from the index only, so the Export tab can show a preview without touching files. The same plan is executed by `app/safety/safe_export.py` (from M0): original bytes are copied into a new job folder in a destination the owner picks outside every source, each copy is verified by SHA-256, and `manifest.json` records the source, new path, checksums and the original names (the reversible rename record).

| Option | Values |
|---|---|
| File names | `default` 2026-10-28_11-02-02_Florence_morning_001.HEIC · `original` 20261028_110202_IMG_0581.HEIC · `place` 2026-10-28_Florence_001.HEIC · `trip` Tuscany-2026_Day-6_Florence-morning_001.HEIC |
| Folders | `day` 2026-10-28_Florence/ (default, as in the brief) · `date` · `event` 2026-10-28/Florence, morning/ · `place` Italy/Florence/ · `flat` |
| Duplicates | `skip` (default) · `alternatives` (Selected/ + Alternatives/) · `include` |

Rules:
- Times are the resolved capture times with accepted clock corrections. Places come from GPS (M4): "in" uses the town, "near" stays "near-Pienza", no GPS means no place in the name.
- A photo without a trustworthy time goes to `undated/` and is named `undated_<original name>`. No date is invented.
- Sequence numbers count per folder in time order, so two photos from the same second never collide; the safe exporter also never overwrites.
- Live Photo, RAW+JPEG and same-name image+video pairs share one name stem; a pair whose main photo is skipped as a duplicate is skipped too.
- Extensions keep their original case (`.HEIC` stays `.HEIC`). Names keep Unicode letters (Ž, č) and drop characters that are invalid in file names.
- Day numbers in the `trip` template count calendar days from the first photo.
- An interrupted export can be resumed into the same job folder: files already there with the right checksum are kept, missing ones are copied, a file with other content is never overwritten.

## Verified

- 71 pytest tests (7 new): names and folders, same-second collision, undated fallback, Live Photo pair, alternatives and other layouts, renamed events with Unicode, verified copies and manifest, resume after a deleted file, API preview and export. Every test checks that the source folder is unchanged.
- `test-10` (19 photos): real export into a scratch folder, 18 of 18 files verified (one duplicate skipped), sources unchanged. Example: `2026-10-28_Florence/2026-10-28_11-02-02_Florence_morning_002.HEIC`. Export tab preview checked in the browser; the destination dialog was not clicked in the test (it opens on the owner's screen).

## Not done

- The Export tab cannot cancel a running export; an interrupted one can be resumed through the API (`resume_dir`), not yet from the page.
- Events still have automatic names unless the owner renames them; the preview shows exactly what will be used.
- Writing EXIF or XMP into the copies (e.g. corrected times, place names) is not done: copies are byte-identical to the originals by design.

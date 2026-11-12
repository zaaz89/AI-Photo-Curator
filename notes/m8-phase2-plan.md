# M8 phase 2 plan: the smart album assistant (native)

Spec: `notes/m8-native-liquid-glass-plan.md` (assistant section; album workbench). Owner said "start" 2026-11-12.

**Goal:** a new album is made by dropping folders into the window; the app proposes who each folder belongs to and the album's name; the album opens on an Overview that shows only what needs a decision; best of each moment is decided in a compare flow; the export for Google Photos runs from the native window.

## Engine (Python, tests first)
1. `POST /api/suggest` `{paths: [...]}` → per folder: photo count, devices, proposed owner (remembered device → person, else EXIF Artist/OwnerName, else a non-generic folder name), date range; for the album: place (one city, or the region when several), country, first and last day. Reads a sample of up to 40 files per folder with ExifTool; places from the offline GeoNames index. Nothing is written.
2. Setting `device_owners` (device → person), saved when an album is created; only on this Mac.
3. Keeper confidence: `_recommend` reports the score margin between the best and the second frame; stored with the group; a group is "decided" when the margin is at least 0.12 or the owner chose.
4. `GET /api/collections/<id>/overview`: clocks (pending suggestions, applied), moments (total, decided automatically, chosen by the owner, need the owner), blurry (total, left out, kept favourites), events and days, descriptions (done / photos, minutes left at the current GPU limit), export (done, photos to export), album facts (people, photos, videos, days, top places).

## App (Swift)
5. New Album wizard (sheet): drop folders or Choose Folders…; one row per folder with the proposed person (editable) and devices; album name proposed from place and dates (editable); Create starts the analysis and opens the album on the Overview while the activity shows progress.
6. Overview (default view of an album): header with name, facts and a strip of the best photos; cards for clocks, moments, blurry, events, descriptions, export, each with one action; live while the analysis runs.
7. Compare flow (sheet): one moment at a time, frames side by side, the recommendation with its reasons in words, ← → to look, Return accepts, K keeps the frame under the cursor, "Accept the rest"; marks the step done at the end.
8. Clocks sheet: each device with the suggestion and Apply / Reject.
9. Export sheet: what will be exported (preview counts), Choose Folder…, progress, Show in Finder; marks the export step.
10. Blurry: a Blurry view in the sidebar (filter) with "Leave out all blurry".
11. Descriptions: card starts the describe job (gentle limit), activity shows it.

## Review focus
- Dropped files instead of folders, the same folder twice, a folder inside another, a folder with no photos: rejected with a clear message.
- ExifTool missing: suggestions fall back to folder names, no crash.
- No GPS anywhere: album name from dates only.
- Overview while the analysis is still running: cards show "analysing" instead of zeros.
- Compare flow on a group whose photo was left out meanwhile.

Out of scope: drag between events, map, localising engine event names (phase 3).

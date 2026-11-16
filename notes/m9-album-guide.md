# M9: the album guide

Owner's request (2026-11-13): the wizard is not intuitive enough, it must lead through the whole process, every part must be editable, and the app looks like apps from 15 years ago. "Make it several levels better." The owner skipped the design questions and asked to start.

## What was wrong (from using the app on the owner's real album)

- Two guides at once: the sidebar's "Album Steps" opened the old web page with 7 steps, the Overview had 6 cards in no order. Nothing said what to do next.
- Numbers that do not add up: 212 in the header, 183 in All Photos, 157 to export, 29 blurry, 29 left out. The owner cannot see what ends up in Google Photos and why.
- Grey boxes with small text and small buttons; photos only in a strip of six frames of the same moment.
- Editing only in the first wizard step. The native app cannot rename an album or chapter, merge or split chapters, edit a description, rename a person, add a folder later, or choose names and folders for the export (the engine can do most of it).

## What people want (research 2026-11-13, sources in the PR)

Merging cameras in true time order is the most common pain. People do not trust an automatic best pick without a reason, want to keep more than one frame of a burst, check eyes on face crops side by side, and prefer a short list ("best 30 to share") to reviewing everything. Everything vs curated must stay separate. Local, no subscription.

## The design

One guide with three steps (since 2026-11-16: Selection, Story, Export; people and clocks moved to their own page and come up only when a clock needs a decision), always visible, every step reachable and editable at any time. The album home says what is next. Photos first, everywhere.

### Sidebar

Album picker; section "Guide": Album (home), 1 Photos & clocks, 2 Selection, 3 Story, 4 Export, each with its state (check, or a count of what waits); section "Library": All Photos, Left Out, Days. "Finish Album…" at the bottom. The old "Album Steps" button and progress gauge go away (the old web window stays in the Window menu, ⌘⇧K).

### Album home

- Hero: the cover photo (from the engine) wide, with the album name over it (rename in place), dates, places, people.
- The funnel: one bar, `taken → left out / blurry / extra frames → in the album`, numbers that add up exactly (the engine computes them from the export plan). Each part opens the photos behind it.
- "Next": one large card with the one thing that waits (clocks to check, moments to choose, then story, then export), with photos of it and one button. While the analysis runs it shows the live phase instead.
- The four steps as photo cards with their state.
- "Best of the album": highlights from the engine, several events, not six frames of one moment.
- People: who took how many, and how many of theirs are in the album.

### Step pages (shared frame)

Header with the step bar (1–4, click to jump), a title and one sentence of what the AI did. A floating glass bar at the bottom: back, what is still open, "Next: <step>".

1. **Photos & clocks.** One card per folder: the person's name editable, folder, count, devices, reveal in Finder; "Add folder" (adds and analyses). Clocks as lanes: one lane per camera over the album's time span with a dot per photo; a suggested shift shows where the dots would move, with Align / No; applied shifts can be undone; manual nudge in a popover.
2. **Selection.** Segments: Moments, Blurry, Left out. Moments inline (not a sheet): a list of moments on the left (needs you / decided / yours), the frames large side by side, face crops under each frame with eyes open or closed, the reason in plain words, "Keep this one" and "Keep this one too" (more than one frame of a moment goes to the album), ← → ↑ ↓ Return F, "Accept the rest". Blurry: a grid where one click keeps or leaves out.
3. **Story.** Days as sections, events as chapters: cover, name editable in place, time and place, photo strip; merge with the previous chapter; open a chapter to see its photos and start a new chapter at a photo. (Descriptions were removed on 2026-11-16: Google Photos writes its own.)
4. **Export.** Three choices as large cards: the whole album for Google Photos (default, corrected time and place in the copies), the best N to share, folders for an archive (by day, event or place; name pattern). A preview of exactly what goes out, then choose a folder, progress, result, Show in Finder, open Google Photos.

### Look

Photo-first cards with large corner radius, cover images, bigger type, hover lift, one accent per step, the AI gradient only where the app works. Liquid Glass stays on navigation and floating controls only (AGENTS.md).

## Engine contract (new in M9)

1. `PATCH /api/collections/<cid>` `{"name": str}` renames the album (1–120 chars after trim). `GET /api/collections` shows the new name.
2. ~~Owner's descriptions~~: built, then removed on 2026-11-16 with the whole descriptions feature (Google Photos writes its own). Migration 9's table stays, unused.
3. Keep more than one frame: a frame of a moment that the owner marked favourite is exported even when it is not the keeper. Same rule in the overview counts.
4. Overview gains:
   - `funnel`: `{taken, left_out, blurry, extra_frames, in_album}` counted by photo (a Live Photo or RAW+JPEG pair is one photo), with `taken == left_out + blurry + extra_frames + in_album` always and `in_album` equal to the photos "Export for Google Photos" copies. The plan also keeps per-file `counts`.
   - `people`: `[{owner, source_id, taken, in_album}]`.
   - `cover_id`: a favourite with the best rank, else the best-ranked photo in the album; null when empty.
   - `highlights`: up to 12 asset ids in the album, best first by rank, at most 2 per event, then sorted by time.
5. Timeline items: `faces.boxes`: up to 6 faces `{x, y, w, h, eyes_closed, looking_away}` normalised to the image with the origin top-left (Apple Vision's bottom-left origin flipped), same size filter as `face_summary`.

All with tests; `tests/test_source_safety.py` must still pass.

## Lean first, deferred

Deferred: choosing the cover by hand, per-person share warnings, learning from the owner's choices, Live Photo / RAW+JPEG shown as one tile in the grid (export already keeps pairs together), VoiceOver pass.

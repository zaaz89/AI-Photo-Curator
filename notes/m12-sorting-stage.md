# M12 idea: the sorting stage ("Sortirnica")

Owner, 2026-11-19: give the app photos and it sorts them by itself, fast and well, and shows what it did and
what it removed; it must look attractive and dynamic while it happens (photos fly up and down and settle
into one overview).

## Today

During an analysis the app gets only the phase and a percentage every 0.7 s; focus, eyes and moments appear
at the end, all at once. Moments are built last (`build_groups`). Only blurry photos and extra frames of a
moment leave the album; screenshots and documents are only asked about in the quick review.

## Stage, four acts

1. Arrival: photos fly in from their folders and settle by day and time (days flow like a paragraph).
2. Quality: a light sweep over each photo; sharp ones get a check, blurry ones lift, turn red and drop into
   "Removed" with the reason.
3. Moments: near-identical frames slide onto the best one, then into "Stacked"; the best one shows ×N.
4. Overview: the album grows into larger photos, a summary line (taken → in the album) and three trays
   (Removed, Stacked, Check), every photo can be put back.

## Spike (2026-11-19, throwaway, `spikes/m12-sorting-stage`, ignored by git)

SwiftUI, one file, timed choreography on a real engine timeline of test-10 copies plus 4 marked synthetic
variants (2 blurred, 2 near-identical frames): 23 photos, 2 removed, 3 stacked in 1 moment, 18 in the album,
about 17 s. Checked by window captures in the background.
Findings: rows per day wasted width (days now flow); the album starting with large photos that shrink as
more arrive reads well; tiles in the trays need the reason on hover or click.

## Needed for the real thing

- Engine: per-photo events while the analysis runs (read, scored, removed with reason, added to a moment),
  read by the app with `since=N`; moments built per day as soon as a day is scored, not at the end.
- App: the stage as the album's first screen while it is analysed, then the overview; trays open, put back
  with one click; replay "Show what you did"; animate by groups above about 400 photos; Reduce Motion =
  fades only.
- Open decision (owner): remove screenshots automatically (reversible, visible in the tray) or keep asking.

## Built (2026-11-19, branch claude/m12-sorting-stage)

- "Sorting" page (sidebar under Album, a line on the album home, opens by itself for a new album,
  `photocurator://go?page=sorting`, `photocurator://replay`). Tiles fly in as the engine reads the photos
  (the app reloads when the count changes), the sweep follows the job's progress during focus and faces, the
  photos are read again once faces are done, verdicts play out as soon as every photo has its results
  (blurry ones lift and drop into Removed), the moments stack at the end, then the overview: summary from the
  album funnel, trays Removed / Stacked into moments / Have a look, each opens with the reason per photo and
  Put back (one or all); Have a look offers "It's fine", Leave out and the quick review.
- Verdicts follow the export rule (`sortVerdict`, CuratorCore/Sorting.swift); the second file of a RAW+JPEG
  or Live Photo pair is not shown (engine: `paired_with` on timeline items, the export's own pairing).
- The screenshot question is open: screenshots and documents stay in the album and show in "Have a look".
- Review (independent, Opus) found and these were fixed: running acts kept writing after a replay
  (generation counter), the end of an analysis was seen before the final photos were read (the app now
  signals after reading them) and late photos could stay unshown (every act ends with a reconcile), pairs
  counted twice, tray tiles spilled into the next tray (last twelve shown, clamped), per-render work at
  1000 photos (one pass, arrivals and thumbnails in batches), gathering onto a keeper outside the album,
  duplicate day ids, glass on a status chip, VoiceOver action on tiles.
- Fixed on the way: "Put back" of a blurry extra frame of a moment set only keep-too and left it out
  (`putBackMarks`, used by the tray, the Blurry grid and the quick review).

Not verified: Reduce Motion, light appearance, VoiceOver, an album above about 300 photos live (the 302-photo
album was shown read-only as an overview), clicks in the tray popover (no synthetic clicks; put back was
checked through the engine's marks endpoint and the stage moved the photo).

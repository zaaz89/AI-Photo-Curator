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

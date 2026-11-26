# M14a: one album, one path

Owner feedback (2026-11-26, translated): "I'm a bit confused, the steps are not understandable; when I add e.g. 3
albums I don't know what the next step is. It needs a complete, smart transformation. The animation while the
analysis runs is great; it must look really premium. I don't see an option to quickly remove albums, photos, the
whole album."

Diagnosis: about ten equal sidebar entries in three sections (guide, library, days); steps named after engine phases
(People & Clocks, Sorting, Selection, Story); no album context menu; a folder could not be removed after the album
was made; Finish / Clear buried at the bottom of the sidebar.

## 1. Information architecture

| Before (M9 to M13) | After (M14a) |
|---|---|
| Sidebar: album picker menu, Guide (Album, People & Clocks, Sorting, Selection, Story, Export), Library (All Photos, Blurry, Left Out, Search), Days, Settings, Clear Working Data | Sidebar: **albums only** (cover, name, status line, progress ring) with "+ New Album" on top, Settings at the bottom |
| Album home with Next card, funnel, step cards, highlights, people | The album's **path**: rail (Photos, Analysis, Questions, Album) + the station + ONE primary button |
| Steps with Back / Next bars and "Step 1 of 3" | Stations derived from the album's data (`AlbumJourney`); completed ones reopen from the rail |
| New Album wizard sheet (drop, owners, name, create + start) | "+ New Album" makes an empty album and opens station 1 (drop folders, chips, Start); the name comes from the folders |
| Clear Working Data at the sidebar bottom | Context menu Remove Album… (⌫, ⌘⌫) and "Clear Working Data…" in the Album station's Done card; one confirmation |
| No way to take a folder out | × on each folder chip (confirmation) → `DELETE /api/collections/<id>/sources/<sid>` |
| Grid destinations in the sidebar | Toolbar **View** menu: Album Path, All Photos, Favourites, Videos, Blurry, Left Out, Search Results, Days ›, Moments, Chapters, People & Clocks |

What moved where:

| Old page | Now |
|---|---|
| Album home (`AlbumHome`) | Station 4 shows `AlbumHero` (cover, counters, people) + export + `DayStory`. Next card, funnel, step cards, highlights and people row are gone (their job is the rail and the primary button). |
| People & Clocks (`StepPhotos`) | Station 1 shows folder chips and a clocks line; the full page is View › People & Clocks (Esc / Back to Album). |
| Sorting (`SortingStage`) | Station 2, unchanged hero, full width between rail and primary bar. Its own Next / Resume / Try Again buttons are gone: the primary bar does that. Replay, Skip, Stop stay. |
| Selection (`StepSelection`) | Station 3 is a summary card stack; the moments page is View › Moments. |
| Story (`StepStory`) | View › Chapters. |
| Export (`StepExport`) | Inline on station 4, without its own button: the primary "Export 187 photos" opens the folder panel (`requestExport`). |
| Finish Album | Remove Album… / Clear Working Data… (same engine call, new copy). |

## 2. The state machine (`CuratorCore/AlbumJourney.swift`)

Input (`JourneyInput`, plain values, Codable so the sidebar can cache it per album): folders, photos, started,
analysing, analysisFailed, progress, daysTotal, daysSettled, openMoments, haveALook, unsureClocks, decisionsDone,
inAlbum, exporting, exportProgress, exported.

First matching row wins:

| Condition | Station | Primary action | Status line (EN) |
|---|---|---|---|
| no folder | Photos | Add Folders… | No photos yet |
| folders, never started | Photos | Start | Ready to start |
| analysis runs | Analysis | Continue (disabled, says why) | Analysing · day 3 of 7 (or · 12 %) |
| last analysis failed | Analysis | Try Again | Stopped by a problem |
| not every day sorted | Analysis | Continue Analysis | Paused · 5 of 7 days sorted |
| questions > 0, not answered, not exported | Questions | Answer 6 questions | 6 questions |
| export runs | Album | Exporting… (disabled) | Exporting · 40 % |
| exported | Album | Open Folder | Exported |
| otherwise | Album | Export 187 photos (disabled at 0) | Ready to export |

- questions = open moments (engine `need_you`) + "Have a look" photos (`sortVerdict == .check`) + unsure clocks; 0
  while photos are not sorted, after "Accept the Rest" / a finished question review (`duplicates` and `times`
  marked), and once exported (albums exported before M14 are done, not sent back).
- sorted days come from the engine (`overview.analysis = {days, settled}`, M14a): a day counts when its signature
  matches (M13 `analysis_days`); albums analysed before M13 count as sorted when every image has a quality row.
  While the analysis runs the live event stream (`SortStream`) can only raise the numbers.
- started = workflow `import` marked (Start marks it) or anything already analysed.
- Adding folders after Start un-marks `duplicates`, `times` and `export`: the new photos are sorted and asked about,
  and the old export no longer counts.
- `canOpen(s)`: the current station and every one before it. `shown(picked)`: the rail's pick if it can open, else
  the current one. `completedStations(from:to:)`: stations passed on a forward move (Analysis → Album completes
  Questions too).
- Words: `status`, `actionTitle`, `waitReason`, `actionSymbol`; plural words `.question` and `.photoObject`
  (Slovenian accusative "Izvozi 1 fotografijo").
- Tests: `mac/Tests/CuratorCoreTests/AlbumJourneyTests.swift` (every row, edges, words, completion, cache round
  trip, confirmations, chip labels).

## 3. Flows

- **New album**: ⌘N / "+ New Album" / empty state → empty album "New Album" arrives in the sidebar (`arrive`) and
  opens on Photos. Drop folders (or click the drop zone) → chips appear; the owner per folder comes from the
  engine's suggestion and the camera memory; the album is renamed from the folders' place and dates while it still
  has the default name. Start → Analysis.
  Dropping folders on the empty state makes the album with them in one go.
- **Analysis**: the Sorting stage, live per day. The bar says "Available when every day is sorted. You can close the
  window; I keep working." Closing the window while analysing keeps the app running (`AppDelegate.keepWorking`);
  when the analysis ends with no main window, the app quits. Stop / Skip / Replay stay on the stage.
- **Questions**: "6 questions · about 2 min", a fanned stack of three of those photos, one row per kind (moments
  with Open Moments, Have a look, clocks with Check Clocks). Primary "Answer 6 questions" = quick review of exactly
  those photos (`questionIds`: frames of unclear moments + Have a look photos; C opens compare). Finishing that
  review answers the questions. "Accept the Rest" marks them answered (undoable, toast). No questions → the path goes
  from Analysis straight to Album with the message "No questions: every photo was clear."
- **Album**: cover, export choices and preview inline, days. Primary "Export 187 photos" (the number follows the
  export choice). After a verified export: celebration (M12f), Done card (Export Again…, Clear Working Data…), primary
  Open Folder (the folder is remembered per album; if it is gone, Open Folder exports again).
- **Remove album**: context menu / ⌫ / ⌘⌫ / Clear Working Data… → "Remove “Rome” from Photo Curator? This removes the
  album and its working data from Photo Curator: the sorting, your choices and the previews. Your photos and the
  exported folder are not touched. This can't be undone." (not exported: "This album isn't exported yet, so your
  choices will be lost." first). Buttons: Remove Album / Keep Album. Refused while the album's job runs.
- **Remove folder**: × on a chip (disabled while a job runs) → "Remove “Ana · iPhone 15” from this album? Its 120
  photos and your choices for them leave the album. The folder and its files are not touched; you can add it again
  later." Remove Folder / Keep Folder.

## 4. Engine (Python)

- `DELETE /api/collections/<id>/sources/<sid>` (`col.remove_source` + `analysis_events.rebuild_changed_days`): deletes
  the source row (assets, capture times, places, chapter and moment memberships, clocks cascade), its event-stream
  rows, content-keyed rows (features, quality, faces, marks, embeddings, …) only when no other photo of the album
  has the same content, moments with fewer than two photos and empty chapters; then rebuilds the days whose photos
  changed and forgets days that are gone. Never opens, moves or deletes a file, never touches a cache file. 409 while
  the album's job runs, 404 for unknown album or folder. Answers `removed_photos`, `photos_left`, `rebuilt_days`,
  `gone_days`.
- `DELETE /api/collections/<id>` (unchanged code, now tested for the whole set): database (events, days, AI data),
  cached thumbnails and previews, video posters; never the photos.
- `GET …/sources` lists each folder's cameras (`devices`, up to 3, most photos first) for the chips.
- `GET …/overview` has `analysis: {days, settled}`.
- Tests: `tests/test_m14_journey.py` (5): removal keeps every file byte-identical (snapshot) and leaves no dangling
  row, keeps the shared copy's analysis and marks, rebuilds only changed days, resume finds nothing to do, the folder
  can be added again; refusals; album removal incl. thumbnails and events; devices; sorted days.

## 5. Motion (Motion tokens; Reduce Motion paths)

| What | Motion | Reduce Motion |
|---|---|---|
| Station change | content settles horizontally (±56 pt offset + cross-fade, direction from the rail order), `settle` | cross-fade (`motionTransition`) |
| Rail indicator | pill slides under the shown station (`matchedGeometryEffect`), `settle` | cross-fade of the pill |
| Station complete | check appears with one bounce (`symbolBounce`) + a ring grows and fades (`arrive`), cleared after `motionBudget` (0.6 s); never blocks | check only |
| Primary label | `contentTransition(.interpolate)` text, `.symbolEffect(.replace)` icon, `quick` | instant |
| Sidebar status | numeric text roll, progress ring trims with `settle`; ring appears / leaves with scale + fade | fade |
| New album | row arrives (`arrive`, move from top + fade) | fade |

One hero motion per screen: the stage's fly-in on Analysis, the completion moment on the rail elsewhere.

## 6. Keys

⌘N New Album · ⌘1 … ⌘4 stations (a station ahead opens the current one) · ⌘↩ the primary action · ⌘⌫ Remove Album… ·
⌫ in the sidebar Remove Album… · ⌘L Left Out · ⌘R / ⇧⌘R Quick Review · Esc on a secondary view: Back to Album · grid
keys unchanged (K, X, F, B, Space, arrows, ⌘A).

## 7. Removed code

`AlbumHome` (except `AlbumHero`, now `AlbumHero.swift`), `NewAlbumWizard`, `FolderRow`, `StepBar`, `StepPage`'s
bottom bar and Next, `Sidebar`, `TripPicker`, `FinishAlbumButton`, `StageLink`, the stage's own Next / Resume buttons,
`GuideStep`, `StepState`, `stepStates`, `nextStep`, `clocksWaiting`, `FlowPage`, menu digits, `finishAlbumTitle/Text`,
`LibraryModel.finishStep/finishPeople/createAlbum/finishAlbum`, `AssistantSheet`, `Destination.home/.step/.sorting`.
49 strings that only those used were removed; `funnel_*` stays (the funnel model and its test remain).

## 8. Open

- Not compiled (Linux). Compile-risk spots are listed in the log entry.
- Reopening the window from the Dock after closing it during an analysis relies on SwiftUI's default reopen for a
  `Window` scene; check it.
- ⌘⌫ is also "delete to line start" in text fields; the menu shortcut may win there (it only opens the confirmation).
- A removed folder's cached thumbnails stay until the album is removed (the route never touches files by design).

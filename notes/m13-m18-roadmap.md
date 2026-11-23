# Roadmap M13 to M18: from good to 10/10

**Status:** plan, written 2026-11-23 by Claude (Cowork) after reading `project-brief.md`, `project-log.md`, `AGENTS.md`,
`notes/m9`, `m10`, `m12`, `app/analysis.py`, `app/quality/*`, `app/duplicates/groups.py`, `app/timeline/event_detector.py`
and `tools/mac-helper/PhotoCuratorHelper.swift`. Owner's request (2026-11-23): "do everything; make it as smart as possible
without additional AI models; everything must look beautiful and dynamic; UX and automation matter most."

**Owner decisions recorded by this request**
- All six items below are wanted, in this order.
- No new AI models. Allowed: what is already in the repo (SigLIP 2 for search, OpenCV/numpy measures) and what ships with
  macOS (Apple Vision, Core Image, AVFoundation, PhotoKit, MapKit). Nothing is downloaded, no photo leaves the Mac (map tiles in M18.2 are fetched from Apple, behind a setting).
- No Google Photos API (owner, 2026-11-23, confirms the 2026-11-16 decision). M17 is a fast manual hand-off instead.

**Rules that still apply to every milestone:** `AGENTS.md` (branch + PR, owner merges, log entry, test-10 for checks,
no synthetic clicks, originals never touched, every string EN + SL in `Strings.swift`, Liquid Glass only on navigation
and floating controls). Each milestone is its own branch and PR. Report what was not verified.

---

## 0. Order and why

| # | Milestone | Why in this place |
|---|---|---|
| M12 | Finish PR #15 + screenshots leave the album | Open work; plan already in the log (2026-11-19 "where I stopped") |
| M13 | Scale: 3,000 files, live per-day pipeline | Nothing else matters if a real two-person trip takes hours or stutters. Biggest hidden risk today. |
| M14 | Autopilot: runs by itself, asks only what it must | Largest UX jump: the owner stops sitting next to the app |
| M15 | Smart without models (Apple Vision built-ins, sun, people coverage, video) | Makes autopilot decisions good enough to trust |
| M16 | Import without friction (Photos library, inbox folder, SD card) | Removes the manual first step |
| M17 | Hand-off to Google Photos (no API) | Makes the manual last step take seconds |
| M18 | Motion and polish pass | Ties it together; Reduce Motion, light mode, VoiceOver verified |

Small separate PR any time: remove Classic View (frozen web page) from the app menu and build, keep the engine endpoints
the native app uses. Less to maintain and test.

---

## M12. Finish what is open

Follow the five-step plan in `project-log.md` (2026-11-19, "Screenshots leave the album by themselves: where I stopped").
Then update PR #15 and ask the owner to merge before M13 starts, so M13 builds on `main`.

Acceptance: Python and Swift tests green; a throwaway album with a copy of one owner screenshot shows it in Removed with
reason "Screenshot" and Put back works.

---

## M13. Scale: real trips, live results

### 13.1 Benchmark set (first, before any optimisation)
- `scripts/make-bench-set.py`: builds `local-data/bench/bench-3000/` from `test-photos/test-10` by copying and
  deterministically varying files (exposure, crop, small blur, re-encode, time shift via a sidecar map the indexer can
  read only in bench mode; never touch EXIF of originals, variants are new files in local-data). Mix to resemble a trip:
  3 sources, 7 days, 8 % near-duplicate bursts, 5 % blurry, 2 % screenshots, 60 videos (short clips generated with
  `ffmpeg` from stills if ffmpeg is present, otherwise skip videos and say so).
- `scripts/bench.sh`: runs the full pipeline headless through `app.cli`, writes `local-data/bench/results-<date>.json`
  with wall time per stage, peak RSS of the engine and helper, photos/s, and the throttle share used.
- Ask the owner before running it (long job rule). Run once at 30 % and once at 100 %.

### 13.2 Budgets (acceptance targets, at 30 % analysis share on the M5 Pro)
| Measure | Target |
|---|---|
| First photos visible on the Sorting page after adding sources | < 5 s |
| Day 1 fully sorted (moments, verdicts) | < 2 min for ~400 photos |
| Whole 3,000-file album | < 25 min |
| Engine peak memory | < 2.5 GB |
| Grid scroll at 3,000 photos | no dropped frames visible in a 10 s window capture (Instruments if available) |
| App memory with 3,000 thumbnails | < 1 GB |

If a budget is missed, fix the largest stage first and record before/after numbers in the log.

### 13.3 Per-day pipeline (the M12 "needed for the real thing" items not yet built)
- Today `analyze_collection` runs each stage over all photos, and `build_groups` runs last. Change to: index all
  (cheap) → clocks → places/events → then **day by day** in chronological order: features → quality → faces → moments
  for that day. A day is "settled" as soon as its moments exist.
- Clock corrections can still change after more days are read. Rule: clocks are computed once from the metadata of all
  files before the per-day loop (metadata is cheap), so later days never move earlier ones. If the owner changes a clock
  later, only affected days are rebuilt.
- Per-photo event stream: `GET /api/collections/<id>/events?since=N` returning ordered events
  `{seq, asset_id, kind: read|scored|removed|stacked|settled_day, reason?, keeper_id?, day}`. Stored in a small
  `analysis_events` table (migration), pruned when the album is finished. The Sorting page reads this instead of
  inferring from reloads.
- Cancel and resume at day granularity: a stopped analysis resumes at the first unsettled day.

### 13.4 App side
- Sorting page consumes the event stream: tiles arrive, drop or stack as events come, not at the end.
- Above ~400 photos animate per day group (already planned), and keep the grid lazy (`LazyVGrid` with fixed cell sizes,
  thumbnails decoded off the main thread at display size, an LRU cache bounded by bytes).

Tests: per-day pipeline equals the old pipeline's results on test-10 (same moments, same verdicts); events are ordered
and complete; resume after cancel produces identical results.

---

## M14. Autopilot

Goal flow: create album, pick dates and sources, close the window. The app works when the Mac is on power and idle,
and later posts one notification: "Tuscany is ready: 302 → 187. 6 questions for you." Done means 0 open questions.

### 14.1 The app keeps running without a window
- Simplest reliable architecture: the existing app stays alive when its last window closes and shows a `MenuBarExtra`
  (status: idle / analysing day 3 of 7 / paused: on battery / ready, with "Open album", "Pause", "Quit").
  No separate launchd agent; the app already owns the engine lifecycle.
- Setting "Keep working in the menu bar when the window is closed" (default on). Quit from the menu bar stops the engine
  as today.
- Optional login item (`SMAppService.mainApp`), default off, setting with explanation.

### 14.2 When it works (scheduler, in the app; the engine only obeys pause/resume)
- Work freely when: on AC power (IOKit `IOPSCopyPowerSourcesInfo`), thermal state nominal or fair
  (`ProcessInfo.thermalState`), and either the owner is idle more than 2 minutes
  (`CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)`) or the owner pressed Start.
- When the owner comes back mid-analysis: drop to the analysis share from Settings; on battery: pause at the next
  photo boundary (the throttle pauses for battery and heat exist; reuse them, move the decision to one place).
- Setting: "Work only when plugged in" (default on). Status always visible in the menu bar and the album home.

### 14.3 One notification, actionable
- `UNUserNotificationCenter`: on album ready ("302 → 187, 6 questions"), actions "Answer now" (opens the quick review
  of open questions) and "Later". No notification per stage. On failure: one notification with the reason.

### 14.4 Questions inbox (the album home is built around it)
- One number on the album home: open questions. Each question is a card the quick review already knows how to show
  (moment with no clear keeper, unsure eyes, clock offset with medium confidence, Have a look items, people naming from
  M15). Ordered by impact: questions that change most photos first (a clock question affects a whole source).
- Album state machine shown as a single line: Reading → Sorting day 3/7 → 6 questions → Ready to export → Exported.
- "Answer in 60 seconds" mode: questions only, keys → ← ⌫, progress ring, finishes on the funnel.

### 14.5 Learns from the owner, explainably (no model, just counting)
- Every Put back and every quick-review answer is a labelled example: (reason, measured value, owner verdict).
- Per album: if the owner puts back ≥ 3 photos removed for the same reason within the same measure band (for example
  subject sharpness between the strict and normal line), move that album's line to the most lenient value that
  would have kept them, re-apply verdicts (strictness is already applied at read time, so no new analysis), and show a
  chip: "You put back 3 soft portraits, so I now keep photos like them. Undo." Never tighten automatically.
- Across albums: store counts in `local-data/settings.json` (`learned` block, no photo data, only thresholds and
  counts). New albums start from the learned values; Settings shows them with "Reset to calibrated".
- Moment keeper: when the owner picks a different keeper than recommended, record which measures differed
  (eyes, face quality, aesthetic, sharpness). After ≥ 5 such picks, nudge `DEFAULT_WEIGHTS` in `scoring.py` and the
  keeper weights in `groups._recommend` by at most ±20 % toward the owner's choices; shown in Settings, resettable.

Tests: scheduler decisions as a pure function of (power, thermal, idle, setting); learning rules on fixtures (puts back
loosen, never tighten, undo restores); notification content strings EN/SL.

---

## M15. As smart as possible without new models

Everything below uses Apple Vision requests that ship with macOS, math, or measures the engine already has. Each new
signal is stored with its value and provenance, is used only above a stated confidence, and is shown in the inspector
as a reason ("Golden hour: sun 4° above the horizon").

### 15.1 Helper v3 (`tools/mac-helper/PhotoCuratorHelper.swift`, one perform per image, run in the existing batch)
Add to the `faces` mode (rename the mode `analyze`, keep `faces` as an alias):
- `VNClassifyImageRequest`: top labels with confidence ≥ 0.3 (scene: food, beach, mountain, church, museum, sunset sky,
  document, etc.). Stored as `scene_labels` with confidences.
- `VNDetectHorizonRequest`: horizon angle (replaces or confirms `horizon_level` in scoring; tilt > 2° is a soft
  minus, never a removal).
- `VNRecognizeTextRequest` in `.fast` mode only when `utility` is true or a document label is present: share of image
  covered by text. High text share = document/receipt/ticket/menu.
- `VNGenerateImageFeaturePrintRequest` on each main face crop (padded 20 %): face print for M15.4. Not an identity
  model; used only for clustering within one album and always confirmed by the owner.
- `VNDetectHumanRectanglesRequest`: people count and size when faces are turned away (backs of heads still count as
  "person in photo").
- `VNGenerateAttentionBasedSaliencyImageRequest`: attention box, used for the cover crop and for thumbnails crop
  (smart square thumbnails that keep the subject).
Bump helper version to 3; the engine re-runs the helper only for photos analysed with v2 when the owner opens the album
(background, day by day), never all at once.

### 15.2 Sun and light (pure math, no model)
- New `app/timeline/sun.py`: solar elevation and azimuth from UTC time and GPS (NOAA algorithm, ~40 lines, tests against
  known values). For photos without GPS use the event's place.
- Labels: golden hour (elevation −4° to 6°), blue hour (−6° to −4°), night (< −6°), midday harsh light (> 50°).
- Used for: event names ("Sunset in Val d'Orcia" only when scene label is sky/sunset AND elevation < 6° AND the camera
  faces roughly west when the compass heading EXIF `GPSImgDirection` exists), a small keeper bonus for golden hour in a
  moment, and the Story chapter titles.

### 15.3 Event names from evidence
- `auto_name` today: place + part of day. Extend with an event kind chosen by vote over the event's photos:
  share of photos with a scene label ≥ 40 % and ≥ 3 photos (food → "Dinner"/"Lunch" by local hour; museum, church,
  beach, hike (mountain/trail + elevation change from GPS altitude > 150 m), city walk (street/building + movement
  > 1.5 km within the event)). Otherwise keep the current name. Owner edits still lock the day.
- Never invent a landmark name. Places stay from GeoNames.

### 15.4 People coverage (the feature competitors do not have)
- Cluster face prints within the album (agglomerative, cosine distance; threshold calibrated on test photos; only
  faces that are main faces, sharp, and large enough). Keep the top 2 to 4 clusters with ≥ 5 photos.
- Priors without any model:
  - Front camera (`LensModel` contains "front") → the face is very likely the owner of that source's device.
  - A source's photos where exactly one main face appears are likely of the *other* person (couples photograph each
    other). Used only to pre-select the suggestion, never as a fact.
- One question in the inbox: "Who is this?" with 6 faces per cluster, choices = source owners + "Someone else" +
  "Skip". After the answer, every photo knows who is in it, with the cluster distance as confidence.
- Coverage card on the album home and in Story: per person, photos in the album; photos of both together; per day.
  Example: "You: 23 · Ana: 141 · Together: 4. Day 3 has no photo of you two together."
- Fairness in keeper choice: within a moment, when two frames are within `CLEAR_MARGIN`, prefer the frame showing the
  person with fewer photos in the album. Shown as a reason.
- If clusters are not clean (silhouette below a calibrated line), the feature hides itself and says why in Settings.
  Measure precision on test-10 and the owner's 236 photos before turning it on by default; report numbers.

### 15.5 Video, smart and cheap
- Helper `video` mode: sample 5 frames (not one), return per-frame mean luminance, luminance variance, Laplacian
  variance (sharpness) and frame-to-frame difference; audio peak level via `AVAssetReader` on the audio track (cheap).
- Rules (removed with reason, Put back available): duration < 1.5 s; ≥ 80 % frames near black (pocket/lens cap);
  all frames blurred and high frame difference (accidental swing). Long videos (> 3 min) go to Have a look, not out.
- Poster frame: the sharpest of the 5 samples with a face if any, not the 1 s frame.

### 15.6 Picking the album, not only cleaning it
- "Album size" control on the album home: Everything good (today) / About 150 / About 60 (highlights). The engine ranks
  the kept photos with a diversity-aware greedy pick (maximal marginal relevance over SigLIP or feature-print
  similarity, which is already computed): score = quality + people coverage bonus + golden hour bonus − similarity to
  already picked; quotas per day proportional to photos taken that day (min 3 per day). Funnel animates live as the
  control moves.
- Automatic cover per album and per day: highest score with attention box, faces open, golden hour bonus.

### 15.7 Documents and screenshots
- After M12, screenshots leave automatically. Documents (utility + text share high) move to a separate tray
  "Travel documents" (tickets, menus, receipts): out of the album, exported only in the archive, easy to put back.
  Owner decides whether this is automatic or a question; default: automatic, visible in the tray, since it mirrors the
  screenshot decision. Ask the owner in the PR.

Tests: sun math against reference values; event naming votes on fixtures; clustering on synthetic prints; coverage
counts; video rules on fixtures; MMR pick deterministic; documents tray reasons. Calibration numbers go to
`notes/m15-smart.md`.

---

## M16. Import without friction

### 16.1 From Apple Photos (PhotoKit, read only)
- New source kind `photos-library` with a date range (from the album dates) and optional album/shared album filter.
- Reading the library needs `PHPhotoLibrary.requestAuthorization(for: .readWrite)` (the only other level, `.addOnly`,
  cannot read). The app never calls `performChanges`; a test or a code search in the PR shows there is no change
  request anywhere. Say this plainly in the permission explanation.
- Originals: `PHAssetResourceManager.writeData` for the original resource(s) into
  `local-data/collections/<id>/library-cache/` (a working copy; counts as working data, deleted on Finish album). Live
  Photos come as photo + paired video resources and are linked as a pair directly (no guessing).
- iCloud originals: `isNetworkAccessAllowed = true` only with a visible progress ("Downloading 84 originals from iCloud,
  1.2 GB") and a size estimate first.
- The engine indexes the cache like a folder; source owner = this Mac's owner by default.

### 16.2 Inbox folder
- Per album, an optional watched folder (default `~/Pictures/Photo Curator Inbox/<album>`), FSEvents in the app; new
  files are indexed incrementally (only new days re-run). Ideal for AirDrop from the partner's phone.
- The album home shows "12 new photos from Ana's inbox, sorting…" and they fly into the Sorting page.

### 16.3 SD cards and cameras
- `NSWorkspace.didMountNotification`; if the volume has `DCIM/`, a banner offers "Add to Tuscany (dates match 412 of
  430 files)". Files are copied into the album's working cache with checksum verification (the card will be ejected),
  never moved, the card is never written.

Tests: date-range filter and pair linking with a PhotoKit fake; inbox incremental index; mount matching by dates.
Verify on the owner's Mac only with the owner present for the permission dialogs.

---

## M17. Hand-off to Google Photos (no API)

Owner decision 2026-11-23: no Google Photos API. The export folder stays the path; make the manual step take seconds.

- After a verified export, one button "Put into Google Photos": reveals the export folder in Finder with all files
  selected (`NSWorkspace.activateFileViewerSelecting`) and opens photos.google.com in the default browser. A short
  sheet says what to do: drag the selection into the browser window, then "Add to album" with the album name, which
  the sheet copies to the clipboard with one click.
- The export folder is named like the album and files are in chronological order, so Google's import keeps the order.
- A checkbox "Done, uploaded to Google Photos" on the album home; ticking it suggests "Finish album". The app never
  checks Google; this is the owner's word.
- Motion: the album cover shrinks into the folder icon, the Finder hand-off happens, the album home shows the final
  state "Exported · 187 photos · Finish album".

Tests: hand-off actions built correctly (paths, clipboard text EN/SL); state change on the checkbox.

---

## M18. Motion and polish

### 18.1 Motion system (one place, `CuratorCore/Motion.swift`)
- Named springs: `arrive` (response 0.45, damping 0.82), `settle` (0.6, 0.9), `drop` (0.35, 0.7), `stack` (0.5, 0.85).
  Every animation in the app uses one of them, so the app feels like one thing.
- Continuity: `matchedGeometryEffect` from Sorting tiles into the album grid; from grid tile to the detail view; from
  the funnel numbers to the trays. Numbers use `.contentTransition(.numericText())`. SF Symbols use symbol effects on
  state changes (check, drop, stack).
- Reduce Motion: every one of these becomes a cross-fade (single switch in Motion.swift). Verify with the system setting.

### 18.2 Album home as a story
- Header: automatic cover (M15.6) with a slow parallax, album name, dates, places, people coverage.
- Day cards: cover of the day, event chips with kind icons (M15.3), golden hour badge, count; a small map of the day's
  route (MapKit snapshot; MapKit fetches tiles from Apple, so behind a setting "Show maps", default on, explained).
- One primary action at a time, driven by the album state machine (M14.4).

### 18.3 First run
- Three screens: what it does, the safety promise (originals are never touched, shown as a short animation), permissions
  asked only when needed (Photos in M16, notifications in M14).

### 18.4 Verification that was missing
- Light appearance, Reduce Motion, VoiceOver (every tile has a label "Photo, 18:42, Pienza, kept, best of 4"),
  keyboard-only use of every page, Dynamic Type sizes where macOS supports them. Window captures in both appearances
  attached to the PR.

---

## How to start (prompt for Claude Code in the repository)

> Read `AGENTS.md`, `project-brief.md`, `project-log.md`, then `notes/m13-m18-roadmap.md`. If the roadmap file is not
> in `notes/` yet, copy it from `~/Documents/Claude Cowork/Projekti/AI Photo Curator/m13-m18-roadmap.md` in your first
> PR and add the owner decisions at its top to `project-brief.md`. Start with M12 (finish PR #15 and the screenshot plan
> from the 2026-11-19 log entry). Then do the milestones in order, one branch and PR each, and stop after each PR for
> the owner to merge. Before any long job (the 3,000-file benchmark), ask. Report tests, numbers and what was not
> verified.

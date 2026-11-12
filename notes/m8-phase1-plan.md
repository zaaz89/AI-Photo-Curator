# M8 phase 1 implementation plan: native shell and library

> For agentic workers: implement task by task (superpowers:executing-plans). Steps use checkboxes.

**Goal:** the owner opens "Photo Curator.app" and gets a native SwiftUI window with Liquid Glass: trips, all photos by day and event, selection, inspector, favourite / leave out / move with undo, Quick Look, search, settings. The guided trip steps of M7 stay reachable in a "Classic View" window until phases 2 and 3 replace them.

**Architecture:** Swift package `mac/` with a library target `CuratorCore` (models, API client, library logic, strings; no SwiftUI) and an executable target `PhotoCurator` (SwiftUI app). The app starts the Python engine like the M7 wrapper and talks to it over the existing local API. Thumbnails come from QuickLookThumbnailing on the original files (read-only), so the grid does not wait on HTTP.

**Tech stack:** Swift 6.4, SwiftUI on macOS 27 (Liquid Glass via standard containers, `GlassEffectContainer` for the selection bar), Swift Testing, Xcode 27 toolchain through `DEVELOPER_DIR` (system `xcode-select` stays on the Command Line Tools).

**Spec:** `notes/m8-native-liquid-glass-plan.md` (approved 2026-11-12 after the spike).

## Global constraints

- macOS 27 minimum; standard containers draw the glass; no glass on photos or list rows; no glass on glass.
- Originals are never written, moved or deleted; the Swift side only reads files (thumbnails, Quick Look).
- Only 127.0.0.1:5014; no network calls elsewhere; no telemetry.
- English default, Slovenian optional (engine setting `ui_language`); every string in both languages.
- Engine API unchanged in phase 1 (all 86 Python tests stay green).
- Test real photos only on `test-10`.

## Review focus

1. Engine not running or slow to start (cold start up to ~25 s): the window shows progress, never a blank grid; quitting stops only an engine the app started.
2. Photos without a capture time ("No date") and videos without a poster: grouped and shown, never dropped.
3. A file moved or deleted after indexing: thumbnail shows a placeholder, Quick Look does not crash.
4. Undo after switching trips: undo entries are cleared when the trip changes (no marks written to the wrong trip).
5. Arrow keys at the edges of a section and in the last short row: the cursor stays inside the list.

---

### Task 1: package, models, API client

**Files:** create `mac/Package.swift`, `mac/Sources/CuratorCore/Models.swift`, `mac/Sources/CuratorCore/APIClient.swift`, `mac/Tests/CuratorCoreTests/APIClientTests.swift`, `mac/Tests/CuratorCoreTests/Fixtures/timeline.json` (synthetic, no personal data).

**Produces:** `struct Trip { id, name, assets }`, `struct Photo` (fields of a timeline item used by the app, `day` / `clock` helpers, `fileURL`), `struct TripEvent`, `struct Timeline { items, events }`, `struct SourceInfo`, `struct EngineSettings`; `final class APIClient(base: URL)` with `trips()`, `timeline(trip:)`, `sources(trip:)`, `setMarks(trip:ids:_ fields: [String: MarkValue])`, `setMark(trip:id:_ fields:)`, `move(trip:ids:toEvent:newName:)`, `search(trip:query:)`, `settings()`, `saveSettings(_ changes:)`; `enum MarkValue { bool, string, null }`.

- [ ] Test `decodesTimeline`: fixture with one photo, one video without poster, one undated photo decodes; `day == "unknown"` for the undated one; `clock == "17:48"`.
- [ ] Test `marksBody`: `setMarks` encodes `{"asset_ids":[1,2],"favorite":true}` and `focus: null` as JSON null (URLProtocol stub).
- [ ] Implement; `swift test` passes.

### Task 2: engine controller and app entry

**Files:** create `mac/Sources/PhotoCurator/App.swift`, `EngineController.swift`, `ClassicWindow.swift`; replace the AppKit wrapper (`tools/mac-app/PhotoCuratorApp.swift` removed), update `scripts/build-mac-app.sh`.

**Produces:** `@MainActor final class EngineController: ObservableObject { state: .starting / .ready / .failed(String); start(); stopIfOwned() }` (venv python, then `uv`; project path from Info.plist `PCProjectPath`; log in `local-data/logs/server.log`; SIGTERM on quit, SIGKILL after 3 s). `ClassicWindow`: WKWebView window on `/` limited to 127.0.0.1, opened from the menu "Window ▸ Classic View".

- [ ] Build the bundle with the script; launch; engine starts; quitting stops it (`pgrep` shows nothing); with an engine already running the app uses it and leaves it running.

### Task 3: library logic

**Files:** create `mac/Sources/CuratorCore/Library.swift`, test `LibraryTests.swift`.

**Produces:** `enum LibraryFilter { all, favourites, leftOut, videos, day(String) }`, `enum SortOrder { time, person, place, quality }`, `func sections(_ photos: [Photo], events: [TripEvent], filter:, sort:) -> [PhotoSection]` (`PhotoSection { id, title, subtitle, photos }`; by event in time order, "No date" last), `struct GridCursor { index; mutating func move(_ dir: Direction, columns: Int, count: Int) }`, `func rangeSelect(from:to:in:) -> Set<Int>`.

- [ ] Tests: left-out photos hidden in `all`, shown in `leftOut`; undated section last; cursor stays in bounds at row ends and in the short last row; range select inclusive both ways.

### Task 4: window, sidebar, grid, Quick Look

**Files:** `MainWindow.swift`, `Sidebar.swift`, `PhotoGrid.swift`, `Thumbnails.swift`, `QuickLook.swift`.

- Sidebar: trip picker section (trips, "New Trip…" opens Classic View for now), Library (All Photos, Favourites, Left Out, Videos), Days.
- Grid: fixed column count from width and tile size; sticky section headers; click, ⌘-click, ⇧-click; arrows; Space → Quick Look (`QLPreviewPanel` with the original file URLs, arrows move inside it); ⌘A; Esc clears.
- Thumbnails: `QLThumbnailGenerator`, `NSCache`, placeholder for missing files; video badge with duration.
- Toolbar: back/forward, View menu (sort, show left-out), size slider, search, inspector toggle, "Export…" (glassProminent, opens Classic View export for now).

- [ ] Run on test-10: 19 photos in 8 events, screenshot light and dark.

### Task 4b: live activity (owner's request 2026-11-12: "dynamic, futuristic, modern, AI")

**Files:** `ActivityView.swift`, `ActivityModel.swift` (polls `GET /api/collections/<cid>/index` every 0.7 s while a job runs, 5 s when idle); `CuratorCore/Activity.swift` with `struct JobStatus { running, progress, status, error }` and `func phase(of status: String) -> ActivityPhase` (indexing, clocks, places, faces, duplicates, search index, describing, exporting, idle) + tests.

- Toolbar: a glass capsule with an animated angular-gradient ring (blue → purple → pink → orange, rotating) around an SF Symbol for the phase, the phase in words and a live percentage; click opens a popover with all phases ticked off as they finish and a Stop button.
- While local AI runs (faces, descriptions, search index) a soft animated gradient glow runs along the window edge, like the system's AI glow; it fades out when the job ends.
- Photos not analysed yet show a light shimmer over the thumbnail; the counters in the sidebar count up as results arrive.
- Reduce Motion: no rotation or glow movement, a static gradient and the percentage only. Animations use TimelineView so nothing animates when no job runs (no idle CPU use).

- [ ] Tests: `phase(of:)` maps the engine's status texts ("Faces (Apple Vision)", "Describing…", "Export done…") to phases; an error status maps to `.failed`.
- [ ] Run "Analyse again" on test-10 and screenshot the window mid-job.

### Task 5: inspector, marks, undo, selection bar, move

**Files:** `Inspector.swift`, `SelectionBar.swift`, `LibraryModel.swift` (the `@MainActor` store).

- Favourite (F), Leave Out (X), focus override, wallpaper; batch on selection; each change registers an undo with the previous values through `UndoManager` (Edit ▸ Undo / ⌘Z); undo stack cleared on trip change.
- Selection bar (2+ selected): Favourite, Leave Out, Keep, Move to Event (menu of events + "New Event…" sheet), Clear.

- [ ] Run on test-10: favourite two photos, undo, redo; move one photo to a new event and back (then restore with the engine's reset for that day).

### Task 6: search, settings, languages

**Files:** `Settings.swift`, `Strings.swift` (in CuratorCore), test `StringsTests.swift`.

- Search field results as a section "Results for …" with the "also searched as" note.
- Settings window (⌘,): language, AI limit, pause on battery, best-of-moment weights.
- `Strings` table EN/SL keyed by language; test that every key has both languages and no empty value.

- [ ] Switch to Slovenian, screenshot.

### Task 7: finish

- [ ] `uv run pytest` (86), `swift test`, build script from a clean `mac/.build`.
- [ ] Update AGENTS.md (build/test commands), project-log, notes status; screenshots of the window in the PR (test-10 only, not committed).
- [ ] Commit, push, PR.

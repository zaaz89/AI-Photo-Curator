# M8 plan: native Mac app with Liquid Glass and a smart trip assistant

Status: approved 2026-11-12 after the spike. Phase 1 built (branch `claude/m8-native-glass`); phases 2–4 open.

## Why

The owner's verdict on M7: the design and the flow are not at the level of Apple's own apps. He wants the Liquid Glass look and a wizard that thinks for him, not a checklist he has to work through.

The M7 window is a web page inside a WKWebView. Liquid Glass is a system material: it samples the content under it, adapts to light and dark, reacts to clicks, and follows the owner's Liquid Glass opacity setting in macOS 27. A web page can only imitate it with `backdrop-filter`, and the imitation will always look and behave differently from Finder or Photos next to it. On macOS 27 the standard SwiftUI and AppKit containers (split view sidebar, toolbar, inspector, sheets, menus, buttons) get Liquid Glass automatically. Getting to Apple's level therefore means a native interface.

Checked on this Mac: macOS 27.2, Xcode 27.2, the SDK has SwiftUI `glassEffect` / `GlassEffectContainer` and AppKit `NSGlassEffectView`.

## Decision proposed

- **Native SwiftUI interface** for the whole app: window, sidebar, toolbar, photo grid, inspector, compare view, assistant, export, settings.
- **The Python engine stays** as it is (indexing, clocks, duplicates, faces, places, events, AI, export). The Swift app talks to it over the existing local API on 127.0.0.1 and starts and stops it, as the M7 wrapper already does. Everything that is tested today keeps working; the 86 tests stay the safety net for the engine.
- **No CSS glass imitation.** The web page stays working during the change but gets no new features; it is removed once the native app covers everything.
- Built from the command line with Swift Package Manager and the Xcode 27 toolchain (`DEVELOPER_DIR=/Applications/Xcode.app/...`), so Codex and Claude can both build it without opening Xcode.

## What the app is (owner, 2026-11-12)

An album workbench, not a photo library. One album is one trip or one event (a wedding, a birthday). The owner imports everyone's photos, edits the whole collection as one album, exports it to Google Photos, and is done. Photos are never kept in the app long term. Consequences: the window is centred on the current album and its progress to the export; other albums are only a list of recent projects; after the export the owner finishes the album, which removes the app's working data for it (analysis, descriptions, marks, thumbnails) after a confirmation, while the photo folders and the exported folder stay untouched. No cross-album library features (search across albums, permanent favourites lists, long-term storage).

## Liquid Glass rules we follow

- Glass only on the navigation layer: sidebar, toolbar, inspector, floating controls (selection bar, compare controls, zoom). Never on photos or list rows. No glass on glass.
- Use the standard containers so the system draws the glass: `NavigationSplitView`, `.toolbar` with item priorities (macOS 27 overflow), `.inspector`, `.searchable`, `.sheet`, `Settings` scene, `.buttonStyle(.glass)` / `.glassProminent` for the one main action.
- Custom glass only for the floating selection bar and the compare controls: `GlassEffectContainer` + `.glassEffect(.regular.interactive())`, so neighbouring buttons merge and respond to the pointer.
- Photos run edge to edge under the toolbar (scroll edge effect), sidebar separate (macOS 27 style), concentric corners, SF Symbols, system font, system accent colour, the owner's light/dark and Liquid Glass opacity settings respected. Reduce Motion and Reduce Transparency respected automatically.

## What the owner will see

**Window.** Sidebar with trips and, inside a trip, Overview, All photos, Best, plus the places and days of the trip. Toolbar: back/forward, view options (grid size, sort, filter as a menu), search field, the main action of the screen (for example "Export…"). Inspector on the right, toggled from the toolbar. Native Quick Look (space bar) for photos and videos. Native menus with all commands and shortcuts, native folder picker (the AppleScript dialog goes away), notifications when a long analysis or export finishes.

**Smart trip assistant (replaces the 7-step checklist).**

1. **Drop the folders.** The owner drags his and his partner's folders (or one trip folder with two subfolders) onto the window. The app proposes who each folder belongs to from the folder name, the EXIF owner/artist fields and the devices it has seen before ("iPhone 16 Pro → Partner" is remembered from the last trip). One confirm.
2. **Name is proposed.** From the GPS places and dates: "Tuscany, 23–30 Oct 2026". Editable, one confirm.
3. **Analysis runs, the owner can already browse.** A live progress card per phase with a time estimate. Photos appear as soon as they are indexed.
4. **Overview: only what needs a decision.** Cards instead of steps, for example:
   - "Phone clocks: the partner's iPhone is 52 s behind. Fix applied." (Undo)
   - "Moments with several shots: 14. 9 decided with high confidence, 5 need you." → opens the compare flow on those 5.
   - "Blurry: 6. 4 left out, 2 kept because they are favourites."
   - "Days and events: 8 events. Rename?"
   - "Descriptions: 0 of 412. Describe now (about 55 min at the gentle GPU limit)."
   - "Ready for Google Photos: 412 photos, 18 videos." → Export.
   Confident decisions are applied automatically and listed so the owner can check them; nothing is deleted, every decision can be undone.
5. **Compare flow.** One moment at a time, frames side by side at large size, the recommendation marked with the reason in plain words ("eyes closed in the other two"). Glass controls: previous / keep this / next. Keys: ← → to look, Return to accept, K to keep the selected frame, "Accept all recommendations" at the end.
6. **Export.** One screen with the summary and one button. When done: verified count, "Show in Finder".

**Live activity (owner, 2026-11-12: "dynamic, futuristic, modern, AI").** Whenever the app works, it shows it: a glass capsule in the toolbar with an animated gradient ring, the current phase in words and a live percentage; a soft animated glow along the window edge while local AI runs; a shimmer over photos not analysed yet; counters that count up. Reduce Motion gives a calm static version.

**Library.** Large, fast grid with smooth zoom (pinch and slider), sections per day and event with sticky headers, multi-select with mouse, keyboard and lasso, floating glass selection bar (Favourite, Leave out, Move to event, Share to wallpaper), drag photos between events (macOS 27 reorder APIs), undo and redo through the system Undo menu.

## Engine changes (Python) the native app needs

- `GET /api/collections/<cid>/overview`: the cards above with counts and what is auto-decided.
- Keeper confidence per duplicate group (score margin between the best and the second frame) and a rule "auto-decided when the margin is clear"; the owner can switch auto-decisions off.
- `POST /api/suggest/sources`: proposed owner per folder (folder name, EXIF Artist/OwnerName, remembered device → person), and a proposed trip name from places and dates.
- Device → person memory in settings (local only).
- Folder paths come from the native picker; the server no longer opens dialogs when the native app runs.
- Tests for each new endpoint, as before.

## Phases (lean first)

0. **Look-and-feel spike (throwaway, first).** A native window with the sidebar, the toolbar, a grid of the test-10 photos, the inspector and the floating glass selection bar, nothing else working. The owner looks at it on his Mac and says yes or what is wrong before the full rebuild starts. Cheap way to make sure "Apple level" means the same thing to both of us.
1. **Native shell and library.** Swift package in `mac/`, API client, engine start/stop, sidebar and trips, grid with selection, keyboard and Quick Look, inspector with marks and undo, search, settings window, EN/SL through a String Catalog.
2. **Assistant.** Drop zone and suggestions, overview cards, compare flow, clocks, blurry, events, descriptions. Engine endpoints and tests.
3. **Export and finish.** Export screen, notifications, menus and shortcuts complete, empty and error states, accessibility pass with VoiceOver, app icon redone in the layered Liquid Glass style if the icon tooling works from the command line (otherwise kept).
4. **Review and PR.** design-critique and accessibility-review skills on screenshots of the real window, fixes, Python and Swift tests, check on test-10 in both languages and both appearances, PR.

Each phase ends with a PR the owner can try; phase 0 ends with a look, not a PR.

## Out of scope for M8

Google Photos connection (owner: wait), iPhone or iPad app, map view, recognising who is in a photo, sharing, iCloud. The web page gets no new features.

## Risks

- **Grid speed with large trips** (2,000+ photos): needs a thumbnail cache on the Swift side and lazy loading; measured on test-10 and, only when the owner asks, on the 236-photo folder.
- **Two interfaces during the change**: the web page may lag behind the engine; it is frozen, not maintained.
- **Codex** cannot see a native window as easily as a web page; screenshots of the window go into PRs, and the engine API stays the shared contract.
- **Toolchain**: `xcode-select` points to the Command Line Tools; builds use `DEVELOPER_DIR` for Xcode 27 instead of changing the system setting.
- Third-party reports say Xcode 27 no longer allows opting out of Liquid Glass; the plan does not rely on opting out.

## Decisions for the owner

1. Native rewrite of the interface with the Python engine kept, starting with the spike (recommended), or Liquid Glass imitation in the current web page (faster, will not reach Apple's level).
2. Confident decisions applied automatically and listed for checking (recommended), or every decision asked.
3. Remember which device belongs to whom across trips (recommended, stored only on this Mac).

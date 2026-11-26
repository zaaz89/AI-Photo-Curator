# AI Photo Curator log

**Purpose:** Full history, decisions and handoffs between Codex (ChatGPT) and Claude Code. Read before working on this project.

Append new entries at the bottom. Update an existing entry in place instead of adding a near-duplicate. Each entry names the agent.

### 2026-11-12 — Repository set up (Claude)
The owner forked `kotyzap/Photo-Curator` v7.0 (commit `1cb56a0`, 101 commits) to `zaaz89/AI-Photo-Curator`. Local copy is in `~/Documents/ChatGPT/AI Photo Curator`; remote `origin` is the fork, `upstream` the original. The fork is public (GitHub does not allow private forks of public repos), so no personal data goes into git.
Added `project-brief.md` (owner's brief, kept as a living document), `AGENTS.md` (shared rules for Codex and Claude), `CLAUDE.md` (imports AGENTS.md), `.gitignore`.
Decision: both Codex and Claude work on this repo through branches and PRs; the owner merges.
Not done: no code was inspected, run or changed. Phase 0 audit has not started.
Next: Phase 0 repository audit (brief section 18 and 22). Agree with the owner which agent does it.

### 2026-11-12 — Phase 0 audit (Claude)
Owner assigned Phase 0 to Claude. Audit is in `notes/phase-0-audit.md` (branch `claude/phase-0-audit`).
Key findings: three code paths move originals (tier toggle, dedup auto-move, move blurry); analysis writes `.dedup_sig_cache.json` into the source folder; dry run creates folders; exports land inside the source folder. Capture time prefers IFD0 `DateTime` over `DateTimeOriginal` (confirmed by probe), no time zones, sort by filename, non-recursive scan. Pillow 11.3.0 has 57 known advisories; fixes need Pillow 12+, which needs Python 3.10+. Runs natively on Apple Silicon with Python 3.9 and 3.12. No tests.
Proposed plan: M0 safety lock (small PR), then M1 multi-source indexing and timeline in a new `app/` package with SQLite and ExifTool.
Not done: no code changed. Duplicate accuracy not measured (no real photos yet).
Next: owner answers the open questions in section 10 of the audit and decides who does M0 and M1.

### 2026-11-12 — Owner decisions after audit (Claude)
ExifTool approved and installed (Homebrew, 13.55). App data goes to `local-data/` in the project folder. Move features are removed from the fork. Real test set is `~/Desktop/photos` (read-only): 236 JPEGs, two Sony cameras, one event, no GPS/HEIC/video. Brief and audit updated.
Next: owner decides who does M0 and M1.

### 2026-11-12 — M0 safety lock (Claude)
Branch `claude/m0-safety-lock`. Python 3.12 via `uv` (`pyproject.toml`, `uv.lock`); Pillow 13.0.0, Werkzeug 3.1.9, pillow-heif 1.8.1; `pip-audit` clean.
Removed every path that moves originals: tier toggle relocation, dedup auto-move, "Move blurry" (`photo_file_organizer.py` deleted). Dedup cache, thumbnails and recents moved to `local-data/`. Exports (TOP N, Phone BG) go through `app/safety/safe_export.py`: new job folder in a user-chosen destination outside the source, exclusive create, SHA-256 verification, `manifest.json`. Capture time now reads `DateTimeOriginal` from the Exif sub-IFD first (EXIF panel and dedup); IFD0 `DateTime` is a labelled fallback. Only one step can run at a time (409 otherwise). Ko-fi badge removed. Also fixed the dead LensModel branch in the EXIF panel (not requested).
Tests: 17 pytest tests pass; a deliberate regression (cache back in the source folder) makes the safety test fail. Real run on `~/Desktop/photos/Engagement` (212 JPEGs): cull 28 s, dedup 42 s (58 marked as duplicates of 186), rank 17 s, export of TOP 10 verified; source folder byte-identical, mtimes unchanged.
Not verified: UI clicked through in a browser (page renders, embedded JS parses); duplicate accuracy on the real set; RAW/HEIC files (none in the real set).
Next: M1 multi-source indexing and timeline.

### 2026-11-12 — M1 multi-source indexing and timeline (Claude)
Branch `claude/m1-timeline`. New `app/` modules: SQLite per collection in `local-data/collections/<slug>/`, recursive read-only importer (SHA-256, incremental, missing files kept), ExifTool batch reader with Pillow fallback, capture-time resolver with rule/confidence/notes, RAW+JPEG and Live Photo pairing, timeline engine, `/timeline` page and `app.cli`. Details: `notes/m1-indexing-timeline.md`.
Tests: 34 pass (17 new for resolver, indexing, API). Real set `~/Desktop/photos`: 236 files indexed in about 4 s, all `high` confidence, re-index skips all, source unchanged. `/timeline` checked in a browser. A collection "Toskana 2026 test" with both folders exists in `local-data/` for the owner to look at.
Not verified: real HEIC/Live Photo/video files, Takeout sidecars. Known limit: sources without offsets can misorder against sources with offsets until clock correction (M2).
Next: M2 (clock offset between devices, exact and near duplicates on the index), after the owner reviews PRs #1–#4.

### 2026-11-12 — M2 device clocks and duplicates (Claude)
Owner said PRs #1–#4 were merged, but GitHub still showed them open; M2 is stacked on `claude/m1-timeline` (branch `claude/m2-clock-duplicates`).
Added: device clocks with GPS and scene-match evidence, suggestions only with ≥3 independent agreeing matches, apply/manual/reject/undo (never automatic, file values kept); duplicate groups (exact, near, similar scene) with keeper recommendation and reasons, owner override stored by content; Duplicates tab and clock panel on `/timeline`. Details: `notes/m2-clocks-duplicates.md`.
Bug found: OpenCV `findFundamentalMat` returns garbage masks when it finds no model; fixed (inliers only with a model).
Tests: 42 pass, 3 runs stable. Real set: no clock suggestion for A7 III (2 matches disagree: −52 s vs −17 s), 25 near-duplicate groups, source unchanged. UI checked in a browser.
Not verified: grouping quality against human judgement, real phones/GPS/HEIC, timing above 236 files.
Next: owner merges #1–#5 and reviews the Duplicates tab; then M3 (local AI: embeddings, descriptions, search).

### 2026-11-12 — PRs #1–#5 merged (Claude)
On the owner's request Claude merged PRs #1–#5 into `main` in order, with merge commits (squash would have duplicated the stacked commits). `main` equals the M2 branch; 42 tests passed on `main`.

### 2026-11-12 — M3 local AI: search, descriptions, tags (Claude)
Branch `claude/m3-local-ai`. Owner approved downloading the models into the project: SigLIP 2 base (1.4 GB) and Qwen3-VL 4B via Ollama (3.3 GB), both Apache 2.0, in `local-data/models/`. Added: search index during indexing, semantic search with local query translation (Slovenian queries work through it), background "Describe photos" job (skips non-keeper duplicates, forbids place/person names, cached per content/model/prompt), AI status API, search box and AI description on `/timeline`, `app.cli search|describe`, `scripts/ollama-serve.sh`, `scripts/download-models.sh`. Details: `notes/m3-local-ai.md`.
Tests: 49 pass (7 new, fake models). Real set: search index 236 photos in 24 s; English queries correct in top 3; Slovenian with translation correct. Descriptions about 10 s per photo; the full run on 202 photos was still going when this was written.
Not done: place names (needs GPS/landmark evidence, M4), faces, review of all descriptions.
Owner feedback: write to Žaž only in Slovenian (no mixed or other languages).
Update: owner asked that the MacBook never runs at full load. Added a GPU time share setting (default 30 %, duty cycle with pauses), background priority for Ollama, model unload after jobs, thermal pause and optional battery pause. Measured: GPU 30 % on average during describing vs 18 % idle. An unrequested background describe run earlier heated the Mac; describing now runs only when the owner starts it or knows about it.
Update: the thinking variant `qwen3-vl:4b` left 177 of 202 descriptions empty (token cap used up by reasoning; empty answers were stored as success). Fixed the code, switched to `qwen3-vl:4b-instruct` and removed the old model (owner's OK). Valid earlier descriptions are kept. New owner rule: test real-photo changes on `test-10` (10 photos in `test-photos/`, git-ignored); the full folder or long AI jobs only on request. On test-10: 9 described in 76 s at 30 %, no errors. The 177 photos of the main collection are not re-described yet.

### 2026-11-12 — M4 places and events (Claude)
Branch `claude/m4-events-places`. Owner added 9 iPhone HEIC photos with GPS (copied into `test-photos/iphone`, test collection now 19 photos) and approved the GeoNames download. Added offline places from GPS (in / near / region, with other names for Slovenian search), automatic events per day (time and place gaps, names from facts), rename / merge / split / undo with locked days, timeline grouped by events, place in photo details, place matches in search, clock differences ≤ 2 s reported as matching. Details: `notes/m4-events-places.md`.
Tests: 64 pass. test-10: 11 s full analysis, 9 places, 8 sensible events, DST change correct, "Firence" finds Florence. Checked in the browser.
Not done: Live Photo pairing on real files (no .MOV in the owner's set), moving single photos between events, landmarks.

### 2026-11-12 — PR #7 merged; M5 smart export (Claude)
PR #7 (M4) merged into `main` on the owner's request. M5 on branch `claude/m5-smart-export`: export plan with four name templates, five folder layouts and three duplicate options; preview in a new Export tab; execution through the verified copy exporter with manifest (original names recorded); pairs share names; undated fallback; resume of interrupted exports. Details: `notes/m5-smart-export.md`.
Tests: 71 pass. test-10: 18 of 18 files exported and verified, sources unchanged; preview checked in the browser.
Not done: cancel and resume buttons on the page, writing metadata into copies (copies stay byte-identical by design).

### 2026-11-12 — PR #8 merged; M6 one app, EN/SL (Claude)
PR #8 (M5) merged. M6 on branch `claude/m6-unified-ui`: owner chose English by default (Slovenian optional) and moving all upstream features at once. New single page with sidebar views, inspector, Quick Look, keyboard; focus tiers, Best photos ranking and phone wallpapers moved onto the collection index; old page, folder routes, map and two dead modules removed. Details: `notes/m6-unified-ui.md`.
Tests: 73 pass. Browser checks on test-10 in both languages and both themes.
Not done: offline map, multi-select, drag between events.

### 2026-11-12 — M7 trip workflow, faces, Google Photos export, Mac app (Claude)
Branch `claude/m7-trip-workflow`. Owner asked to finish the program around the real workflow (two people's trip photos → sorted, best of each moment, descriptions → one folder for Google Photos) with Apple-style design, and decided: metadata into exported copies only, Apple Vision for face quality (no identities), a real Mac app. Added a Swift helper (Apple Vision faces: eyes, gaze, face quality; AVFoundation video posters), face-aware keeper with weights in Settings, favourite / left-out marks, moving photos between events, the trip checklist, the new trip sheet, a rewritten UI (macOS HIG), the "Export for Google Photos" preset that writes time, place, description and rating into the copies with ExifTool and reads them back, and `dist/Photo Curator.app` (AppKit + WKWebView, starts and stops the server). Details: `notes/m7-trip-workflow-plan.md`.
Tests: 86 pass (13 new). test-10: 13 of 19 photos with faces; Google Photos export 18 of 18 copies written and verified, sources unchanged. UI checked in both languages and both themes; the Mac window checked on screen.
Not verified: eye thresholds on real closed-eye photos; Google Photos reading the description; VoiceOver.
Next: owner tries the app on the next trip folder; Google Photos connection later (owner asked to wait).

### 2026-11-12 — PR #10 merged; M8 phase 1: native app with Liquid Glass (Claude)
PR #10 (M7) merged on the owner's request. Owner: design and UX not at Apple's level; wants Liquid Glass, a smart assistant, and dynamic "AI" feedback whenever the app works. Plan `notes/m8-native-liquid-glass-plan.md` (native SwiftUI interface, Python engine kept) approved after a throwaway spike window. Phase 1 on branch `claude/m8-native-glass` (plan `notes/m8-phase1-plan.md`): Swift package `mac/` (CuratorCore + app), engine start/stop, sidebar with trips, library and days, grid by day and event with keyboard, Quick Look on the originals, inspector, favourite / leave out / focus / wallpaper with system undo and redo, floating glass selection bar, move to event, search, settings window, EN/SL, live activity (gradient ring with phase and percentage in the toolbar, AI glow on the window edge, shimmer on photos being analysed). The M7 trip steps stay in a Classic View window until phases 2–3.
Tests: 14 Swift + 86 Python pass. Checked on test-10 by keystrokes (favourite, undo, redo, multi-select) and screenshots in English and Slovenian; 9 photos of test-10 described during the activity check.
Not verified: light appearance and Reduce Motion in the native window; VoiceOver; Quick Look and lasso by mouse.
Next: owner tries the app; phase 2 (assistant: drop folders, suggestions, overview cards, compare flow).
Update (same day): owner clarified the purpose: an album workbench per trip or event, edited as a whole and exported to Google Photos; nothing is kept long term. The app now says "Album", the sidebar shows the album (All Photos, Left Out, Days) and its progress (steps done, Album Steps, Export for Google Photos, Finish Album). New engine endpoint `DELETE /api/collections/<id>` ("Finish album") removes only the album's working data (database, AI data, its cached thumbnails and posters), refuses while the album's job runs, and never touches the photo folders (3 new Python tests). Review fixes from an independent code review landed with tests (wrong-trip marks, hidden selection, write order and undo, single engine start, Quick Look, single-letter keys). Tests: Swift 20, Python 89.

### 2026-11-12 — M8 phase 2: the album assistant (Claude)
Owner asked where the wizard is (the native one was planned for phase 2) and said start. Plan `notes/m8-phase2-plan.md`. Engine: `POST /api/suggest` (reads a sample of each folder with ExifTool, proposes the person from remembered devices, EXIF Artist/Owner or a non-generic folder name, devices, dates, album place from GeoNames; device-named folders such as "iPhone" are not taken as people), setting `device_owners`, keeper margin per moment (clear when the lead is at least 0.12), `GET /api/collections/<id>/overview`. App: New Album wizard (⌘N, drop folders or choose, proposals editable, opens by itself on first start), Overview as the album's home with cards (clocks, best of each moment, blurry, days and events, descriptions, export) that show "still analysing" while the analysis runs and update live, Moments sheet (frames side by side, recommendation with reasons, ← → Return K, accept the rest), Clocks sheet, Export sheet (preview, choose folder, progress, Show in Finder), Blurry view with "Leave out all blurry", steps with nothing to decide count as done, EN/SL counted words.
Checked end to end in the app with copies of the test photos: wizard → album "Tuscany, 23–28 Oct 2026" → live analysis (40 s) → moment chosen with keys → export 16 files verified → Finish Album (9 MB freed); test photos byte-identical before and after; the test album and the device memory it created were removed afterwards.
Bugs found and fixed while checking: the moments sheet lost its place when the album reloaded (state now in the model), Escape did not close it, the export card counted extra frames, a duplicate string key would have crashed the app (test added).
Tests: Python 96, Swift 25.
Independent review of phase 2 (Opus): no critical findings; all important ones fixed with tests first. Nested folders, the app data folder and empty paths are refused by the wizard, and a half-made album is removed. A left-out frame is never the keeper, so a moment cannot vanish from the export. Keeper choices go through the ordered write queue and errors are shown. The export card counts exactly what the Google Photos export copies (blurry photos included in the rule). "Analysing" only covers the analysis, not describing or exporting. The export sheet clears the previous result and shows refusals. The photo strip is linear. "Blurry" follows the owner's own focus mark. Devices are remembered only when they clearly belong to one folder. Shared copies are described once. The folder count is capped and ExifTool timeouts are caught. Exports are refused into any album's photo folders, not only this album's. Glass is no longer on a photo. Tests: Python 102, Swift 28. Deferred minors: polling load on huge albums, album name not refreshed after the first drop, no UI to view or clear remembered devices, "people" counts folders, country fallback for multi-region trips, plural of "%d files", moments analysed before the margin existed show as "needs you" until the album is analysed again.

### 2026-11-13 — M9: the album guide (Claude)
Branch `claude/m9-album-guide` (on top of PR #11, not merged yet). Owner: the wizard is not intuitive, it must lead through the whole process with every part editable, and the app looks 15 years old; "make it several levels better", skipped the design questions. Looked at the app on the owner's album (screenshot only) and at research on culling apps (Reddit itself was not reachable; sources were Apple/Adobe forums, MacRumors, reviews). Design: `notes/m9-album-guide.md`.
App: one guide in four steps (Photos & Clocks, Selection, Story, Export) in the sidebar and as a step bar on every page, each step reachable at any time, a floating Back / Next bar. Album home: cover photo with the album name (rename in place), "Next" card with the one thing that waits, a funnel whose parts add up (taken → left out / blurry / extra frames → in the album; each part opens its photos), step cards with photos, best of the album, people with their share. Step 1: people cards (rename in place, folder, devices, Show in Finder), Add folder (drop or choose; analyses only the new photos), clocks as lanes with the suggested shift drawn, Align / No / Undo and a manual shift. Step 2: moments inline (list, frames side by side sized to the window, face crops with eyes open/closed, reason in words, Keep this one, Keep this one too, ← → ↑ ↓ Return F), Blurry and Left out grids with one-click keep / leave out. Step 3: days and chapters (cover, rename in place, merge with previous, open; new chapter at a photo; editable descriptions; reset a day), AI descriptions card. Step 4: whole album for Google Photos / best N to share / folders for an archive, preview of exactly the photos that go out, export with progress, Show in Finder, Open Google Photos. Old Overview cards, the moments/clocks/export sheets and the sidebar's "Album Steps" button (old web page) removed; the web window stays in the Window menu (⌘⇧K).
Engine (contract in the design note): `PATCH /api/collections/<id>` renames, `POST .../assets/<id>/description` stores the owner's text by content (wins in timeline, export metadata and search), a favourite extra frame of a moment is exported, overview gains `funnel` (built from the export plan, adds up exactly, pairs follow their primary), `people`, `cover_id`, `highlights` (≤ 12, ≤ 2 per event), timeline faces gain `boxes` (top-left origin). Migration 9 adds `owner_descriptions` (additive).
Tests: Python 116 (14 new), Swift 36 (8 new guide tests). Checked in the app on test-10 with clicks, keys and screenshots in English and Slovenian: every page renders, Keep too moves the frame into the album (funnel 18 → 19) and back, Return chooses and marks Selection done, best-5 export (5 files) and Google Photos export (18 files) verified, test photos byte-identical before and after. Found and fixed while checking: a text with `fixedSize` outside a scroll view shifted the whole window up on step pages; frames of a moment overflowed the window; export cards did not fill the width.
Not verified: the description editor, chapter rename/merge/split and Add folder by hand in the app (endpoints have tests); face crops on real faces (test-10's only moment has small faces below the size filter); light appearance; VoiceOver. The test album's keeper was reset; its "export" step is marked done from the test exports.
Later the same day: Return in a description closed the chapter sheet (Done was the default action) and lost the text; Done now closes with Escape, and descriptions and names are also saved when their view closes. The description box focuses on a click anywhere in it.
**Where I stopped (owner asked to stop for the day):** checking the description editor in the chapter sheet by automated clicks and typing. Typed text still did not reach the field: the accessibility focus stayed on the sheet, so either the synthetic clicks do not start editing (the test tool was just fixed to send a click count; not re-checked) or the multi-line `TextField` in the sheet's grid does not take focus. First thing next time: try it by hand in the app; if it fails there too, switch to an explicit editor (pencil → popover with a text editor and Save). An independent code review of commit 365d886 was started and its findings are not in yet; read and fix them first. Nothing is pushed and there is no PR for M9 yet.
Independent review of 365d886 (arrived after the stop, not fixed yet; fix in this order):
1. High: Keep in the Blurry grid only clears "left out", but the export drops blurry photos unless they are favourite or have a focus override, so "In album" is shown for photos that are not exported. Keep must set the same thing the export reads; the grid should list what the funnel's "blurry" counts.
2. High: `LibraryModel.change()` lacks the `tripId == loadedTripId` guard; with the new save-on-disappear, a chapter/person/description edit can be written into another album after switching albums (ids are per album). Add the guard or capture the album id when the view appears.
3. Medium: album rename state survives an album switch on the home page (could rename the new album). Reset on `tripId` change, check the id on commit.
4. Medium: `funnel.in_album` counts files (Live Photo / RAW pairs = 2) while the Export page counts photos; home and Export can show different numbers. Count photos in the funnel labels or label them as files.
5. Medium: clearing an AI-only description shows an empty field while the export still writes the AI text; there is no "no description". Decide: empty = no description (engine stores an empty owner text) or show the AI text again.
6. Low-medium: `_album_summary` in `app/assistant.py` is outside the try; an error there fails the whole overview.
7. Low: `addFolders` can half-finish (first folder added, no analysis, no reload); only the last refusal is shown.
8. Low: step 1 counts as done only without pending clocks; Next with an unanswered suggestion keeps Home pointing at step 1. Honour the owner's mark like Selection does.
9. Unverified: face boxes on rotated photos (portrait HEIC); the helper may not pass EXIF orientation to Vision.
Reviewer confirmed correct: funnel identity, favourite extra frames exported, owner's text wins everywhere, migration 9 additive, rename endpoint, no path touches source files, all strings and format specifiers match.
Next: the review items above, then the description editor, then hand checks (chapter rename/merge/split, Add folder), then push and open the PR (after PR #11 is merged).

### 2026-11-16 — M9: review fixes, descriptions removed (Claude)
Same branch. Fixed all review findings from 2026-11-13: a kept blurry photo now gets the owner's focus mark "soft" so the export takes it (the grid shows "In album" by the export's own rule, Keep all / Leave all out likewise); every edit carries the album it was made in, so a name committed after switching albums goes to its own album, and edits without an album are refused while another album loads; album rename keeps its album; the funnel and people count photos (a Live Photo or RAW+JPEG pair is one photo, so Home and Export show the same number; the plan keeps per-file counts too); the overview survives a failing summary; Add folder tries every folder, reports all refusals together and analyses when any was added; step 1 counts as done once the owner moves on from an unanswered clock suggestion. Face boxes checked on rotated (orientation 6) iPhone photos of test-10: they sit on the faces, Vision applies the orientation.
Owner's decision: remove everything about descriptions, Google Photos writes its own. Removed the Story descriptions card, the chapter description editor (it also had the focus problem from 2026-11-13), the inspector's description and tags, the owner-description endpoint and module, and the description in exported copies (corrected time, place and favourites are still written). Migration 9's table stays unused so albums keep their schema version. Brief and `notes/m9-album-guide.md` updated.
Tests: Python 115, Swift 39 (new: blurry rule, step 1, album-safe edits). Checked in the app on test-10: Story without descriptions, Export texts and layout (three choices in a row, full-width run card).
Open: light appearance, VoiceOver; chapter rename/merge/split and Add folder by hand (endpoints have tests).

### 2026-11-16 (later) — faster, simpler: three steps, lazy search, no description model (Claude)
Owner: speed it up and simplify; approved all four proposals. Measured first on a fresh album of the test-10 photos (19): 41 s in all, of which focus 12.7 s, faces 12.9 s, search index 10.8 s. Cause: focus and faces ran under the 30 % AI duty cycle and one photo at a time.
Changes: focus scoring runs in worker processes and faces in three Apple Vision batches at once, both without the duty cycle (thermal and battery pauses stay); the search index is no longer part of the analysis, the first search builds it in the background and the app searches again by itself. Same photos now: about 11 s to a finished analysis (focus 1.4 s, faces 5.4 s); focus tiers, sharpness and faces identical to before. The Qwen description model (3.1 GB, Ollama) was deleted with the owner's OK and dropped from `scripts/download-models.sh` and AGENTS.md; models now take 1.4 GB.
The guide has three steps (Selection, Story, Export). People and clocks have their own page (sidebar, and a button in the people section of the home); a clock suggestion nobody answered comes up on the home before the steps. Review fixes from the second review: the blurry grid's "In album" follows the full export rule (an extra frame of a moment goes in only as keep-too), the album summary logs its errors.
Not done: Slovenian queries are no longer translated before search (the translation used the deleted Qwen model); semantic search still works on the original words. Typing into the toolbar search could not be driven by the test tool; the lazy search was checked through the engine (first search answers "preparing" and builds 19 vectors, the next returns results).
Tests: Python 116, Swift 40.

### 2026-11-16 — M10: quick review, faces side by side, quality check v2 (Claude)
Branch `claude/m10-quick-review` (on top of `claude/m9-album-guide`, PR #12). Owner: smart, intuitive features and commands; decide fast with the arrows (→ yes, ← no) with a back step; the quality check must be good at closed eyes and blur, and a sharp subject on a blurred background is not a fault; no Google Photos connection; then "do all of it now". Plan: `notes/m10-plan.md`. Reddit could not be read (it refuses automated access, also in Chrome); the research used DPReview, culling-tool reviews, GitHub issues and Apple's docs.
Quick review (⌘R, toolbar, Selection step, album home): full window, one photo at a time. By default only where a decision is needed (owner's correction): every frame of a moment with several near-identical shots and photos with a real problem; the other photos stay in the album ("the other N stay in the album"). → Yes (keep, following the export rule: a blurry photo gets the owner's focus mark, an extra frame becomes keep-too), ← No (leave out), ⌫ or ⌘Z Back (restores the photo's earlier marks, as many steps as needed), Space skip, F favourite, hold Z zoom on the face, E faces large, ? keys. Every decision is written at once; it resumes where it stopped; end card with counts. For a moment, the same people are shown side by side in every frame (one column per frame, one row per person matched by position, eyes open / closed / can't tell, a mark for looking away); click a column to see that frame. The Selection step shows the same matched faces. Guide menu: ⌘R, ⇧⌘R all photos, ⌘0–6 pages.
Quality check v2 (helper + engine, built by a subagent, checked here): sharpness measured on the main faces or the salient subject, so bokeh is never blurry, plus a movement cue; eyes per main face open / closed / unsure (small, turned, looking down, sunglasses, low confidence), compared with the same face in the other frames of a moment; Apple's aesthetics score and utility flag (screenshots, receipts, documents); keeper ranks eyes, subject sharpness, capture quality, aesthetics; "all frames have a problem" flag. Migration 10 (`faces.vision_json`, `subject_focus`); existing albums re-measure once when analysed again.
Calibration on the owner's 236 photos (Engagement and Palazzo Piccolomini; a third subfolder "toskana" added on 13 Nov was not used: a first run that included it was stopped and removed): analysis 77 s. Blur: the old whole-image check had called 30 photos blurry, all bokeh or low light, sharp at 100 %; the subject check calls none blurry and 5 soft (incl. real motion; one is a false soft, harmless). Eyes: on 30 turned faces the landmark values were checked against the crops and are useless (closed eyes in kisses read as open), so turned faces stay "unsure"; frontal "closed" was right; "open" now starts at 0.25 (0.18-0.24 included half-closed and looking-down eyes). All 539 files in ~/Desktop/photos byte-identical afterwards; the temporary albums were removed.
Tests: Python 130, Swift 44. Checked in the app with keys and screenshots (test-10 and a temporary album with a duplicated selfie): decisions-only queue (3 of 19), yes/no/back restore the exact state, resume, face comparison beside the photo.
Not done / open: "show only undecided" in the grids (dropped: every photo already has a state); calibration on phone photos (the "toskana" folder) only with the owner's OK; light appearance, VoiceOver.
Later the same day (owner: "work so you don't disturb me"): added a background control channel `photocurator://` (pages, album, quick review, review keys, window size), delivered with `open -g` so the app never comes to the front and no synthetic clicks or keys are sent; off unless the `automation` user default is true; checks now capture the window with `screencapture -l`. Rule added to AGENTS.md. Checked: the frontmost app stayed the owner's (Chrome, then ChatGPT) while the review was opened and driven. Fixed the quick review dropping or doubling decisions on fast or held keys (a decision is recorded at once; the flash is visual only); three fast → then three Back give 4/19 and back to 1/19 with the album unchanged. Swift tests 45.
Independent review of M10 (second run; the first stopped on a network error), all fixed: a held arrow repeated decisions (now one per press); photos measured by an old helper were never measured again (the helper version is now stored, photos are re-measured only by a newer helper, an old one never loops); sharpness used a halved decode for some devices (now full decode, then the working size); ⌘Z outside the review now goes through the responder chain (text fields, sheets and the Classic window undo their own changes); the hidden page under the review no longer takes keys (the window content is disabled while it is open); "Yes" on another frame of a moment sets a new `keep` mark (migration 11) instead of favourite, so no 5 stars in the export; byte-identical copies are not asked about; a reload no longer overwrites decisions made while it was on its way; switching albums closes the review without touching bookmarks; faces in the Selection step use a frame with faces as reference when the keeper has none; Escape closes the keys card first; changing the filter while the review is open works; "other N stay in the album" counts only photos that do; the background channel's window command picks the main window, and AGENTS.md says to switch the channel off after a check. Tests: Python 132, Swift 46. Checked in the background (the owner's Chrome stayed in front): "Yes" on an extra frame sets keep, not favourite, and Back clears it.
Calibration on phone photos (owner's OK; ~/Desktop/photos/toskana: 255 iPhone photos, 47 videos; analysis 178 s, temporary album, removed; all originals byte-identical afterwards). Findings: "closed" was right on all 3 frontal cases; in the 0.18-0.25 range almost every phone selfie had clearly open eyes while the same range in the professional set was downcast or half-closed eyes, and the head pitch separates them (pro: 9 of 11 tipped down, phone: 33 of 42 level) - so in that range a level head (pitch < 0.05) now counts as open (one professional case with closed eyes and a level head becomes "open"; moments still compare frames). Dark sunglasses measured up to 0.47 on the eye/cheek line, bare eyes from 0.46: the dark-lens line moved from 0.45 to 0.48 (mirror lenses stay uncaught, harmless). Phone eyes now: 137 open, 3 closed, 93 unsure (pro: 20 open, 1 closed, 189 unsure, mostly turned faces). Blur on phone photos: 1 blurry (a face smeared by movement while the food in front is sharp, checked at 100 %: right), 4 soft (night shots, a car selfie). Utility flag: 21 photos, mostly screenshots, a door-code note, menus and wine labels, but also a market stall and a wine cellar; they are only asked about in the quick review, never left out automatically. Tests: Python 133.


### 2026-11-16 — Moments: all frames visible, no sideways scroll (Claude)
Owner: when a moment has many frames, wrap them so all are visible; do not hide them to the right. The compare view now lays the frames out with `frameLayout` (CuratorCore): every column count is tried, frames wrap into rows, and the layout with the largest frames that still fits wins; only when frames would be under 180 points does the grid scroll down, never sideways. Narrow cells get smaller face crops and the two buttons one under the other, still with words. Checked on the owner's 212-photo album through the background channel (moment 1, 4 frames, all on screen). Tests: Swift 50 (4 new layout tests).

### 2026-11-16 — M11: settings in the app (Claude)
Branch `claude/m11-smart-settings` (on top of `claude/m10-quick-review`, PR #13). Owner: "the GPU must go above 30 % if I want; I want smart settings in the app". Found first: the setting existed only in ⌘, (25/30/50/100), and since the M9 speed-up it slowed only the search index, because focus and faces had left the duty cycle. Owner chose: a slider 10-100 % for all work, settings visible in the app with explanations and a time estimate, strictness of the quality check (not: keeper profiles, export defaults). Note: `notes/m11-smart-settings.md`.
Engine: `ai_gpu_share` 10-100; focus, faces and subject sharpness go through the throttle again, parallel work in rounds with a rest after each (`throttle.throttled_map`); the analysis stores seconds per photo in `local-data/speed.json` and `GET /api/settings` returns it; `quality_strictness` lenient | normal | strict moves the blur and closed-eye lines when results are read (normal = calibrated, unchanged). App: a Settings page in the main window (sidebar button, a line on the album home, `go?page=settings`), the same page in ⌘,; slider with what it applies to and the estimate for the album, battery pause, thermal note; three strictness levels with a sentence each and the album's blurry count; keeper weights; language.
Checked: test-10 in a throwaway data folder 13.9 s at 100 %, 31.7 s at 30 % (estimate 28 s), photos byte-identical. Owner's album Tuscany (255 photos, read only): lenient 0 blurry / 2 soft / 0 closed eyes, normal 1 / 4 / 3 (as calibrated), strict 2 / 17 / 3. In the app through the background channel: settings page, strict → Blurry 2 in the sidebar and on the page, estimate "about 6 min at this setting, about 3 min at 100 %", home line; strictness set back to normal. `speed.json` was seeded with the test-10 measurement; the next analysis replaces it. On the last restart the app came to the front (not wanted; the background channel is off again).
Tests: Python 141, Swift 54.
Not verified: lenient and strict are not calibrated on their own (the 17 strict "soft" photos not looked at one by one); light appearance, VoiceOver.

### 2026-11-19 — M12 idea: the sorting stage, spike (Claude)
Owner: the app should sort photos by itself, fast and well, show what it did and removed, and look attractive and dynamic while it happens. Proposal and spike in `notes/m12-sorting-stage.md`; the throwaway spike is in `spikes/m12-sorting-stage` (ignored by git): photos fly in by day, a sweep checks each one, blurry ones drop into "Removed", near-identical frames stack behind the best one, then one overview with three trays. Data: an engine timeline of test-10 copies plus 4 marked synthetic variants, analysed in a throwaway data folder. Checked by window captures in the background.
Open: owner's verdict on the feel; decision on removing screenshots automatically; then engine events and the real stage.

### 2026-11-19 — M12: the sorting stage, built (Claude)
Same branch. Owner: "build it" after the spike. Details and the review in `notes/m12-sorting-stage.md`.
App: Sorting page driven by the real analysis (arrival by day, sweep with progress, blurry photos drop into Removed, moments stack, overview with three trays and put back), Replay, home link, opens for a new album. Engine: `paired_with` on timeline items (export pairing). CuratorCore: `sortVerdict`, `sortReason`, `stageFlow`, `stagger`, `putBackMarks`. Fix: putting back a blurry extra frame now sets both marks (tray, Blurry grid, quick review). Fix (M11 test): the throttle test no longer depends on work taking more than 0 s.
Checked in the app in the background on three throwaway albums made from test-10 copies plus 4 marked synthetic variants: live analysis 25-34 s, then reveal, stacking and overview "Taken: 23 → in the album: 18", replay, a put back through the marks endpoint; the albums were removed afterwards. The owner's Tuscany album was shown read only once (an album switch over the background channel failed at first; fixed: the channel reads the album list first).
Tests: Python 141, Swift 61. Independent review: all findings fixed (see note).
Open: screenshots stay asked about (owner's decision pending); Reduce Motion, light appearance and VoiceOver not checked.

### 2026-11-19 (later) — Screenshots leave the album by themselves: where I stopped (Claude)
Owner's decision (answer to the open question of M12): "remove automatically". Nothing is changed in the code yet; the owner asked to pause. Findings so far, all read only:
- iPhone screenshots carry EXIF `UserComment = "Screenshot"` (checked with ExifTool on the owner's three PNG screenshots in `toskana`, 1320×2868, no Make). The market stall, wine cellar, receipts and menus that Apple's utility flag catches are camera HEICs (Make Apple) without that mark, so they are not screenshots. `image000000.jpeg` (no Make, 481×640, a received picture) and `IMG_0274.HEIC` (no Make) have no mark either.
- `metadata_raw` keeps only the tags in `app/metadata/exif_reader.py` `TAGS`; `UserComment` is not among them, so existing albums do not have it.
Plan (owner agreed to "remove automatically"; screenshots only, documents and the rest of the utility flag stay in "Have a look"):
1. Engine: add `UserComment` to `TAGS`; migration 12 `screenshot_checks(asset_id PRIMARY KEY, screenshot, reason)`; new `app/quality/screenshots.py` with `is_screenshot(user_comment, filename, make)` (mark "Screenshot", or no camera Make and a screenshot file name such as `Screenshot…`, `Posnetek zaslona…`) and `detect(conn)` run in `analysis.py` right after indexing (reads ExifTool again only for make-less images not checked yet, so old albums are filled in too).
2. Export plan: screenshots not kept by the owner (`keep` or favourite) are left out in the `no_blurry` and `best` selections (the album exports), reason `screenshot`; `counts` and `photo_counts` get `screenshots`; the funnel in `app/assistant.py` gets `screenshots` (and `EMPTY_SUMMARY`). `all` (archive) keeps them.
3. Timeline items: `screenshot: true/false`.
4. App: `Photo.screenshot`; `goesToAlbumDespiteFocus` also needs `!screenshot || keep`; `sortReason` → `screenshot`, string `why2_screenshot`; `putBackMarks` sets `keep` for a screenshot; `needsALook` is false for a screenshot (the quick review stops asking); funnel: `Overview.Funnel.screenshots` (optional, 0) and a `screenshots` part in `funnelParts` with `funnel_`/`funnelHelp_` strings and where its click goes (`AlbumHome.FunnelView.open`).
5. Tests (Python: rule, export exclusion and keep override, funnel identity; Swift: rule, put back, funnel part), check on a throwaway album with a screenshot copy, update PR #15.

### 2026-11-23 — Screenshots leave the album by themselves, built (Claude, Cowork)
Built the five-step plan of the 2026-11-19 entry on `claude/m12-sorting-stage` (details in `notes/m12-sorting-stage.md`).
Owner asked Cowork to do the work directly. Python: 156 passed (141 + 15 new) in a Linux container with ExifTool 12.x.
Swift: changed and tests added, but NOT compiled or run (no Swift toolchain reachable there): run `scripts/test-mac.sh`
and `scripts/build-mac-app.sh` on the Mac first. Delivered as a git bundle (no push access from the container).
Also added `notes/m13-m18-roadmap.md` (owner's plan for M13 to M18, 2026-11-23: no new AI models; no Google Photos API).
Open: compile and verify the Swift side, update PR #15, merge; then M13.


### 2026-11-24 — M12b: design system, phase 1 (Claude, Cowork)
Branch `claude/m12b-design-system` (on top of the M12 PR branch). Goal: M13 to M18 screens are built from one source of tokens and motion. Note: `notes/m12b-design-system.md`.
Added: `CuratorCore/DesignTokens.swift` (spacing and radius scales, `MotionToken` with the spring specs and the Reduce Motion variant, no SwiftUI), `PhotoCurator/DesignSystem/Tokens.swift` (`Space`, `Radius`, `TypeRole`, `StatusColor`), `PhotoCurator/DesignSystem/Motion.swift` (`Motion.arrive/settle/drop/stack/quick/fade/sweep/ambient`, `withMotion`, `.motionAnimation`; Reduce Motion gives a 0.15 s cross-fade or nothing). Every animation call site in the app now uses a Motion name (the sorting stage's own Reduce Motion switch kept); kept / removed / look / stacked colours use `StatusColor` (visible changes: the stage's removed red is now system red, stacked is system cyan, the funnel's extra frames cyan instead of blue and blurry red instead of orange). Ratchet `scripts/check-design-tokens.sh` with baseline `mac/design-tokens-baseline.txt` (padding 156, cornerRadius 34, fontSystemSize 20, animationCurve 0): passes. Test `DesignTokensTests.swift` (4 tests).
NOT compiled, Swift tests NOT run (Linux container, no Swift toolchain): run `scripts/test-mac.sh` and `scripts/build-mac-app.sh` on the Mac first. Python: `uv run pytest -q` 150 passed, 4 failed, 2 skipped; the 4 failures are EXIF/GPS tests and ExifTool is not installed in this container (no Python was changed).
Open: compile and look at the app (sorting stage timing changed to the named springs, light/dark, Reduce Motion); then migrate radii, paddings and font sizes in small PRs (plan in the note).

### 2026-11-24, Claude (Cowork): M12b decisions taken by the agent
- Tray and counter "Removed / Odstranjeno" renamed to "Left out / Izpuščeno" (keys unchanged): nothing is deleted, the old word broke trust (UX audit P0). Hints now say "not deleted".
- `drop` motion set to spring 0.55 / 0.72 (0.35 felt abrupt next to the old 0.8). `removed` stays system red; the softer (1, .42, .42) gives white text only ~2.8:1.
- Not compiled, not run. Owner can reverse any of these in the PR.

### 2026-11-24 — M12c: UX audit P0 fixes #2 to #7 (Claude (Cowork))
Branch `claude/m12c-ux-p0` (on top of `claude/m12b-design-system`). Source: P0 rows of `notes/m12b-ux-audit.md` (#1 was done in M12b).
- #2 Stage states: `CuratorCore/StageUX.swift` `stageState` (running / failed with the engine's reason / stopped with "not analysed yet: N" / waiting / done). Header shows them with a primary "Resume" or "Analyse again"; Next becomes secondary then. Unknown phases say "Working" instead of "Arranging by day and time".
- #3 No dead end: "Skip animation" (Esc, and Space through an invisible second button) from the first frame of any act or replay; Next always visible, disabled with "Available when sorting is done" until the overview.
- #4 Huge counts: above `stageChoreographyLimit` (400) the stage does not animate per photo, does not preload thumbnails, and shows the album as a lazy grid by day (`StageGrid`, scrollable). A settled album whose flow does not fit also switches to the grid (nothing clipped). `ThumbnailCache` makes at most 12 thumbnails at once; a cell that scrolled away gives up its turn. Up to 400 photos the animation is unchanged.
- #5 VoiceOver: `stageTileAccessibilityLabel` (file, verdict, reason, frames stacked behind, video) and `gridTileAccessibilityLabel` (adds focus tier, eyes closed, another frame, not in album + reason). Hidden tray tiles are hidden from VoiceOver.
- #6 Contrast: `StatusColor.removedFill/onRemoved` (6.5:1), `onLook` (8:1), `lookText/keptText` (5.0:1 light, 5.7:1 dark) used in grid badges, selection chips, inspector pills and the stage "Have a look" glyph.
- #7 Undo: one `DesignSystem/UndoToast.swift` (text + Undo + dismiss, 6 s, VoiceOver announcement) fed by `LibraryModel.offerUndo`, using the window's undo manager (so it works from the tray popover). Wired to Put back, Put all back, It's fine, Leave out, Accept the Rest (now registers undo: reviewed moments and the step mark go back). "Split this day automatically again…" asks first, naming the day and chapter count.
- 18 new strings (EN + SL), 1 changed (`stagePhase_other`). Tests: `StageUXTests.swift` (7 tests); `StringsTests` knows the `toast_` family. `scripts/check-design-tokens.sh`: OK, no baseline change.
NOT compiled, NOT run (Linux container, no Swift toolchain): run `scripts/test-mac.sh` and `scripts/build-mac-app.sh` first.
Check visually (test-10, then the 236 folder only if the owner asks): Stop during an analysis → "Sorting stopped" + Resume; Skip with Esc and Space during arrival and replay; Next disabled text fits in the 34 pt row while analysing; the 236-photo stage still animates and does not switch to the grid at the owner's window size (it would only if the settled flow overflows); tray Put back → toast at the bottom with Undo, Undo restores, Cmd+Z agrees; Accept the Rest → toast, Undo; split-again dialog; grid badges in light and dark; VoiceOver on a stage tile.

### 2026-11-24 (later) — M12b and M12c compiled on the Mac, PRs #16 and #17 (Claude)
Imported both branches from the Cowork bundle and compiled them on the Mac (Xcode 27 toolchain). Base #15 (58022bc, screenshots) also compiled first: 63 Swift tests pass, so its Swift side is verified.
Fixes (minimal, no design changes): M12b `scripts/check-design-tokens.sh` used `declare -A`, which macOS bash 3.2 lacks (exit 2); now one variable per metric, counts match the baseline (156 / 34 / 20 / 0), a lowered baseline fails as it should. M12c `SortingStage.swift` could not see `StageFlow()` (memberwise init of a public struct is internal); added `public init() {}` in `Sorting.swift`. M12c rebased onto M12b after the script fix, no conflicts.
Results: M12b 67 Swift tests, M12c 74 Swift tests, all pass, no warnings in changed files; `scripts/build-mac-app.sh` OK on both; `uv run pytest` 156 passed; token check OK.
PRs: #16 "M12b: design system + UX audit" (base `claude/m12-sorting-stage`), #17 "M12c: UX P0 fixes" (base `claude/m12b-design-system`). Merge in order #15, #16, #17.
Open: nothing was looked at in the app. Visual checks are listed in each PR (stage timing with named springs, new status colours in light/dark, Reduce Motion, "Left out" wording, stopped/failed states, Skip, grid above 400, undo toast, VoiceOver).

### 2026-11-24 — M12d: UX audit P1 for Quick Review and compare (#9, #11, #12, #18, #19) (Claude (Cowork))
Branch `claude/m12d-ux-p1` (on top of M12c). Another agent edits the grid, stage, export, album home and menus in
parallel; this one only touched Quick Review, a new compare view, and minimal hooks in Selection and LibraryModel.
- #12 + #19 Real 100%: Z now toggles (no key-up to lose) between the whole photo and 100% of the original, decoded with
  ImageIO (`CGImageSourceCreateThumbnailAtIndex` at full size, orientation applied, read only) off the main thread, only
  for the photo on screen. Centred on the largest main face (no saliency in the model yet), drag pans, the 2048 px
  thumbnail is shown enlarged with a spinner until the original is ready, and stays with a note if it can't be decoded.
  Resets on photo change, focus loss and scene-phase change. `PhotoCurator/ZoomablePhoto.swift`, maths in
  `CuratorCore/ReviewZoom.swift` (`ZoomMath`).
- #11 Compare: `PhotoCurator/CompareView.swift` + `CompareSession` (CuratorCore). Keeper left, challenger right, synced
  zoom and pan (one shared centre), 1/2 pick through `LibraryModel.keep(group:photo:)` (the call Selection uses),
  ←/→ cycle the challenger, Esc or C exits. Opened with C or the "Compare" button in Quick Review's moment panel, and
  from Selection's moment card ("Compare", `LibraryModel.startCompare(group:)`: the quick review opens on the compare
  view and closes with it; Selection reloads its moments after pending writes).
- #9 VoiceOver: main photo label = `gridTileAccessibilityLabel`; value = zoom state + decision while it flashes;
  named actions keep / leave out / skip / back / zoom / compare; announcement after each decision ("Kept, 12 of 80"),
  after Back and after a pick. Keys not in the keymap (up/down, anything with ⌘⌥⌃) are no longer swallowed.
- #18 (review side): `ReviewKeymap` in CuratorCore, used by Quick Review, compare, the automation channel and the
  keys card; documented in `notes/m12b-design-system.md` ("Review keymap"). Grid side left to the other agent.
- Reduce Motion: the decision flash scales only without Reduce Motion (cross-fade with it); the photo leaves in the
  direction of its key (→ / ←) only without Reduce Motion.
- Automation keys added: `compare`, `pick1`, `pick2`. 26 new strings EN + SL, `keyZoom` reworded (toggle, not hold).
Tests: `ReviewKeymapTests.swift` (12 tests: keymap, pass-through, keys card, announcements, zoom target/fit/100%/clamp/
pan, compare cycling and picks). Token check OK (cornerRadius 34 → 33, baseline not lowered to avoid a conflict with the
parallel branch).
NOT compiled, NOT run (Linux container, no Swift toolchain): run `scripts/test-mac.sh` and `scripts/build-mac-app.sh`.
Check visually (test-10, near-duplicate pair): Z on a Sony A7 IV file shows real 100% (pixel-sharp, not the blurry
thumbnail), spinner then sharp; centred on the face; drag pans and stops at the edges; Z again fits; zoom resets after
→, after Cmd+Tab and after clicking the filter picker. C on the pair: two panes, Z zooms both on the same spot, drag in
one pans both, ← → change the right frame, 2 makes it the keeper (badge moves left, Selection shows "chosen by you"
after closing), Esc returns. Selection → "Compare" → Esc returns to Selection. Reduce Motion on: flash and photo change
cross-fade. VoiceOver: the photo reads file, time, owner, status; Kept/Left out is announced; VO-arrows still move.
Memory: a 61 MP original is about 240 MB while zoomed (two in compare); check Activity Monitor on the 236 folder only if
the owner asks.

### 2026-11-24 — M12e: UX audit P1, flow (#8, #10, #13 to #17, #20 to #22) (Claude (Cowork))
Branch `claude/m12e-ux-p1-flow` (on top of compiled M12c). Source: rows 8, 10, 13 to 17, 20 to 22 of `notes/m12b-ux-audit.md`. QuickReview.swift and Thumbnails.swift not touched (another agent works there in parallel).
- #8 Errors: `CuratorCore/FlowUX.swift` maps engine texts and HTTP codes to `ErrorKind` + a human sentence (`humanError`, EN + SL), raw text kept for Details. New `DesignSystem/ErrorBanner.swift`: sticky (no timer), Details disclosure, Try Again when an action exists, Dismiss, VoiceOver announcement. `LibraryModel.report(_:retry:)` replaces every `message = describe(error)`; `message` stays for info (now also announced). `stopJob` failures are shown, not swallowed. Engine start failure is `EngineStartFailure` (localised, path only in Details); the UI language is remembered in UserDefaults so the start screen is in Slovenian before the engine answers. "Engine" copy → "background service" / "storitev v ozadju".
- #10 Reduce Motion: `.motionTransition(_:)` (DesignSystem/Motion.swift) turns slides, pushes and scales into a cross-fade; used for the stage header push, source chips, verdict and stack badges, message/error banners, selection bar, undo toast, grid heart, wizard rows. `ScanBand` is a still highlight under Reduce Motion. Selection frame scale is off under Reduce Motion.
- #13 Tray: cells 150 pt high, 3 columns, popover 680 wide; arrows move focus (↑/↓ by a row), Space opens Quick Look on the focused photo, double-click too; focus ring drawn in accent.
- #14 Stage: settled album tiles are focusable (Tab), arrows move, Space = Quick Look, Return = same as a click; a click on an album tile now opens Quick Look (was a dead end). Large-album grid tiles too.
- #15 Guide menu follows the flow: Home ⌘0, People & Clocks ⌘1, Sorting ⌘2 (new), Selection ⌘3, Story ⌘4, Export ⌘5, Settings; All Photos ⌘6, Left Out ⌘7 (`FlowPage.menuDigit`, decoupled from `GuideStep.number`). Sidebar Guide section in the same order (People & Clocks moved up from Library). Copy: "Three steps to the album" → "Steps to the album"; unused "of 7 steps" and "Album Steps" keys removed; "noTripsText" no longer points to "Album Steps".
- #16 One primary per screen: toolbar Export not prominent; Selection's Quick Review is `.glass`; on Export the bottom bar's "Back to album" is `.glass` (Export button is the primary); on Home the stage link moved into the funnel card.
- #17 Funnel "screenshots" opens the Left out tray (`library.openTray(.removed)` → stage opens the popover). "Have a look" tray button is "Review These Photos" and calls `library.startReview(.decisions, ids:)`. INTEGRATION NEEDED: QuickReview.swift must take the subset: in `.onAppear` use `begin(filter, ids: library.takeReviewSubset())` instead of `begin(filter, ids: nil)`; until then it starts the normal Decisions review (which contains those photos).
- #18 (keys only): grid K = keep in album, X = leave out (no longer a toggle), Space = Quick Look, Esc closes Quick Look first then clears the selection, ⌘Z undo; listed in the Photo menu. `gridKeyAction` in CuratorCore. Should match `ReviewKeymap` from the parallel branch (→/K keep, ←/X leave out).
- #20 Export: Cancel Export next to the progress (engine now honours cancel for exports: `_run_smart_export` stops between files, status "Cancelled"; test added), "Export cancelled" state, preview failure shows the error with Try Again (no endless spinner), job errors are human text with Details and Try Again.
- #21 Grid badge "Screenshot" / "Document" (icon + text) with the reason as tooltip and in the VoiceOver label; blurry tier badge gets the reason as tooltip (`autoBadge` in CuratorCore).
- #22 "Finish Album…" → "Clear Working Data…", title "Clear working data for “X”?" with "Not exported yet." first when not exported, button "Clear Data", body leads with the consequence.
- Strings: 30 new, 13 changed, 2 removed (EN + SL). Tests: `FlowUXTests.swift` (9 tests); `LibraryModelTests` failed-folder test now checks the banner. Token check OK, cornerRadius baseline lowered 34 → 33. Python: `uv run pytest -q` 151 passed, 4 failed (same ExifTool/GPS tests as before, no ExifTool here), 2 skipped.
NOT compiled, Swift tests NOT run (Linux container): run `scripts/test-mac.sh` and `scripts/build-mac-app.sh` first.
Check visually (test-10): error banner (stop the engine, then mark a photo) in light/dark, Details and Try Again, VoiceOver reads it; start screen when the engine fails, in Slovenian; Reduce Motion on: stage header title change, scan, badges, banners fade without sliding; stage settled: Tab into tiles, arrows, Space opens Quick Look, focus ring visible on rotated tiles; tray popover: arrows, Space, Quick Look panel opens above the popover; funnel "screenshots" opens the Left out popover; Guide menu order and ⌘2; Home with the stage link inside the funnel card; Export: Cancel mid-copy, "Export cancelled", preview error (stop engine) with Try Again; grid Screenshot/Document badges at small tile sizes; Clear Working Data dialog title.

### 2026-11-24, Claude (Cowork): M12d + M12e merged into one branch
- `claude/m12d-ux-p1` now holds both P1 halves (Quick Review/compare and flow/errors/keyboard); only conflict was this log. Wired #17: Quick Review starts with `library.takeReviewSubset()`, so "Review These Photos" in the Have a look tray reviews only the tray's photos.
- Not compiled. Build order on the Mac: `scripts/test-mac.sh`, `scripts/build-mac-app.sh`, `uv run pytest`, `bash scripts/check-design-tokens.sh`.

### 2026-11-26 — M12f: motion and delight (roadmap M18.1 to M18.3, audit #30) (Claude (Cowork))
Branch `claude/m12f-motion-delight`. Another agent edits SortingStage, GuideChrome, StepPhotos, Thumbnails and QuickReview
in parallel; this branch touches SortingStage (TrayCard only) and GuideChrome (`CardStyle` hover only), nothing in the others.
- Rules: `notes/m12b-design-system.md` → "Motion choreography": never block input, every motion ≤ 0.6 s (`motionBudget`),
  one hero motion per screen, no per-photo choreography above 400 photos. Every new motion goes through `Motion` and has a
  Reduce Motion path.
- Micro-interactions (`DesignSystem/Interactions.swift`): `.hoverLift()`, `.buttonStyle(.pressableCard)`, `.symbolBounce(on:)`.
  Applied to step cards, day cards, highlights, tray cards and every `.card(hover: true)` (export choices, chapters).
  Haptics: `LibraryModel.decisionPulse` (keep / leave out / compare pick) → `.sensoryFeedback` in MainWindow.
- Continuity: inspector photo settles in on a new selection; heart and leave-out icons use `symbolEffect(.replace)`; numbers
  roll (`numericText`) in the funnel, home counters, step badges, day cards, export percent; tray symbols bounce once when
  the trays settle; undo toast and error banner symbols bounce on arrival. No `matchedGeometryEffect` grid ↔ inspector or
  into Quick Look (system panel; the tile stays in the grid): reasons in the notes.
- Album home as a story (M18.2 without maps or new engine data): cover = `albumCover` (engine cover while in the album, else
  a highlight, else the best kept photo) with slow parallax; dates and places under the name; counters (in album, taken,
  days, chapters); new "Day by day" row (`dayCards`: best photo of the day, counts, chapter names); NextCard stays the one
  primary action; funnel card kept, its header now has "Replay the sorting" / "Watch the sorting" (audit #30: always on Home).
- First run (M18.3): three screens (what it does, "originals are never touched" with a copy-into-folder animation, start),
  once (`FirstRun.seenKey` = `firstRunSeen.v1`), Skip / Esc, ← → and Return; "Create an Album" opens the wizard when there
  is no album. Automation: `photocurator://firstrun?page=0|1|2`, `photocurator://firstrun?close=1`.
- Celebration: after a verified export the cover shrinks into a folder, the folder bounces, the count rolls up; once per
  export folder (`shouldCelebrateExport`); buttons usable at once; Reduce Motion = a still check mark.
- CuratorCore `Delight.swift` (pure) + `DelightTests.swift` (8 tests) + 3 automation expectations. 19 new strings EN + SL
  (block "// M12f motion and delight" at the end of `Strings.swift`). Token check OK, baseline unchanged.
NOT compiled, Swift tests NOT run (Linux container): `scripts/test-mac.sh`, `scripts/build-mac-app.sh`,
`bash scripts/check-design-tokens.sh`.
Visual checklist (test-10, window capture, no synthetic input):
1. `defaults delete si.beehive.photocurator firstRunSeen.v1`, start: first run appears once; `firstrun?page=1` shows the copy
   travelling into the folder and the lock/folder bounce; page dots slide; relaunch: not shown again.
2. Home: cover is a kept photo (leave the engine's cover out and reload: cover changes); scroll: cover moves slower than the
   page, no edge shows; counters pill row legible on bright and dark covers; Day by day row: covers, counts, chips; a day
   opens All Photos on its cover; "Replay the sorting" in the funnel header opens the stage.
3. Hover any card: small lift, no layout jump; press a step/day card: press-in; Reduce Motion on: no scale, no parallax,
   no bounces, celebration shows a check mark.
4. Grid: select photos with arrows: inspector photo settles in; F / X: heart and leave-out icons morph; with a Force Touch
   trackpad, K / X and compare 1/2 give a light tick.
5. Sorting stage at settle: tray icons bounce once; Put back changes a count and bounces again; no bounce during fly-in.
6. Export test-10: percent rolls; at the end the cover drops into the folder once (go to Home and back: no replay); Show in
   Finder clickable during the moment.
7. Undo toast and error banner: symbol bounces once.

### 2026-11-26, Claude (Cowork): M12g: UX audit P2, accessibility and copy (#23 to #29, #31 to #33)
Branch `claude/m12g-ux-p2`. Not touched (motion pass owns them): AlbumHome, PhotoGrid, MainWindow, Inspector; row 30 skipped.
- #23 `FaceCrop` label from Strings (`eyes_closed/unsure/open`, `eyes_away`). #24 Stage counters and source chips are one VoiceOver element each ("12 in the album", "Name, 3 of 10 photos read"). #25 small stage tiles keep a 10 pt glyph for "to look at" / "left out"; all glyphs with Differentiate Without Colour.
- #26 `.scaledFont` (ScaledMetric) for stage/page titles, counters, percent; ratchet `fontSystemSize` 20 to 13. Not done: AlbumHome hero/step titles (file not mine).
- #27 stage secondary text 0.6/0.65 to 0.78 (`StageInk`), dark scrim under tray glass. #31 decision: keep the dark stage, `stageDarkSurface()` shared by Stage and Quick Review, Increase Contrast handled by `StageInk` (see notes/m12b-design-system.md).
- #28 `trCode` / `Strings.codeText`: unknown engine code shows "Other reason" / "Other note" / "This folder could not be used" and is logged. #29 `stepsProgress` was already gone; `exportHelp` lost "classic view for now"; `phase_describing` now "Working" (key kept, the phase enum still exists).
- #32 Return: Next on the settled Stage (Resume / Analyse Again when those are primary), Align on the first pending clock lane. #33 thumbnail failure label ("Cannot read file" / "No preview available"), 260 px stand-in and spinner for the large Quick Review photo.
- Strings: 12 new (block `// M12g a11y and copy`), 2 changed. Tests: `StringsTests` (codeText, keys). Token check OK after `--update` (fontSystemSize 13); the other agent may also touch the baseline file.
NOT compiled, Swift tests NOT run. Compile risks: `ScaledSystemFont` init with `_size = ScaledMetric(...)`; `DefaultActionKey` ViewModifier with if/else body; `ViewThatFits` in Thumbnail; `@EnvironmentObject` now in `Thumbnail` and `FaceCrop`; `Logger` in LibraryModel; `Result<NSImage, Failure>` across the actor.
Check visually (test-10): Stage in dark with Increase Contrast and Reduce Transparency on (tray text, glows); tiny tiles show orange/left-out glyphs; Return on the Stage after settling goes to Selection; Return on People & Clocks aligns the first clock; rename a file in test-photos then open it: "Cannot read file" label; Quick Review shows the small photo with a spinner, then sharp; VoiceOver on counters and chips; text size larger in System Settings for the stage titles.

### 2026-11-26, Claude (Cowork): M12f + M12g merged
- `claude/m12f-motion-delight` holds M12f (motion, Album Home story, first run, export celebration) and M12g (P2 a11y and copy). Conflicts were only appended blocks (Strings, notes, log); 543 string keys, no duplicates; token check OK (156/32/13/0).
- Stack: m12c (#17) → m12d (P1) → m12f (this). None of m12d/m12f compiled yet. Build m12d first, then m12f.

### 2026-11-26 (later) — M12d and M12f compiled on the Mac, PRs #18 and #19 (Claude)
Imported `claude/m12d-ux-p1` and `claude/m12f-motion-delight` from the Cowork bundle (it was in `~/Downloads`, not on the Desktop) and ran the four checks on the Mac (Xcode 27 toolchain).
- M12d: compiled and passed as delivered, no fix commit. 95 Swift tests (86 + 9), `scripts/build-mac-app.sh` OK, `uv run pytest` 157 passed, token check OK (156/32/20/0). Three new compiler warnings in `LibraryModel.swift` (`[weak self]` inside a `Task` that captures self strongly: `runSearch`, `analyse`, `stopJob` retry closures); harmless, left as written.
- M12f: one compile error, fixed: `ThumbnailCache.Failure` did not conform to `Error`, which `Result<NSImage, Failure>` needs (`Thumbnails.swift`). The other M12g risk spots compiled as written. 105 Swift tests (96 + 9), build OK, pytest 157 passed, token check OK (156/32/13/0), no new warnings. No rebase needed (m12d unchanged, m12f already on its tip).
PRs: #18 "M12d: UX P1" (base `claude/m12c-ux-p0`), #19 "M12f: motion, album story, first run, P2 a11y" (base `claude/m12d-ux-p1`). Merge order: #15, #16, #17, #18, #19.
Open: nothing was looked at in the running app; the visual checklists are in #18 and #19.

### 2026-11-26 — M13: scale, per-day pipeline, live event stream (Claude (Cowork))
Branch `claude/m13-scale` (base: M12f, PR #19). Design, budgets, bench how-to: `notes/m13-scale.md`.
- 13.1 `scripts/make-bench-set.py` (deterministic 3,000-file trip from test-10: 3 sources, 7 days, 8 % bursts, 5 % blurry,
  2 % screenshots, 60 ffmpeg clips; new files in `local-data/bench/`, originals only read; times spread by a sidecar map the
  indexer reads only with `PHOTOCURATOR_BENCH_TIMES` and only inside the bench folder). `scripts/bench.sh` (bash 3.2) +
  `app.cli bench` (`app/bench.py`): fresh data folder per run, JSON with stage times, first day settled, peak RSS engine/helper,
  photos/s, throttle share used. Sets over 200 files need `--yes`.
- 13.2 budgets in `notes/m13-scale.md` §1.
- 13.3 `analyze_collection` is per day: index → screenshots → clocks → places/events once, then per day features → quality →
  faces → videos → moments; keepers chosen again after the last day (focus verdicts are album-relative). Migration 13:
  `analysis_events`, `analysis_days`. `GET /api/collections/<id>/events?since=N`. Resume at the first unsettled day; clock
  change rebuilds only changed days; keeper choice no longer re-runs ORB. Decision in the brief §5.2: moments never span days.
  Old order kept as `analyze_collection_all_at_once`.
- 13.4 CuratorCore `AnalysisEvents.swift` (stream model, pacing, "2 of 7 days sorted") + `ByteLRU.swift` (byte-bounded LRU,
  thumbnail buckets incl. 160); `APIClient.analysisEvents`; `LibraryModel.pollEvents` (only while analysing); Sorting stage
  reveals/stacks settled days live, snaps per day above 400; `ThumbnailCache` on ByteLRU (384 MB) with Quick Look bitmaps.
  1 new string EN + SL (`// M13 scale`). Token check OK (156/32/13/0, unchanged).
Tests: `uv run pytest` 163 passed (157 + 6 new in `tests/test_m13_scale.py`), ExifTool installed in the Linux container.
NOT compiled, Swift tests NOT run: run `scripts/test-mac.sh` and `scripts/build-mac-app.sh`. Compile-risk spots:
`SortStream.merge` (switch expression), `ByteLRU` optional-chained dictionary writes, `rep.cgImage` → `NSImage(cgImage:size:)`
in `Thumbnails.swift`, `readyFilter()` closures in `SortingStage.swift`, `pollEvents` in `LibraryModel.swift`.
Bench: smoke-tested only on a 30-file set made from 4 generated JPEGs (Linux, no helper). NOT run on test-10 or the 3,000 set:
ask the owner before running it (long AI job); then record the numbers against the budgets here.
Open: first-photo latency, app memory and grid frame rate need a by-hand check on the Mac; grid marks do not write events.

### 2026-11-26 (evening) — M13 compiled and benched; #15 to #20 merged into main (Claude)
Owner authorised the agent to merge this time. Imported `claude/m13-scale` from the Cowork bundle and ran the four checks on the Mac: 115 Swift tests (106 + 9), `scripts/build-mac-app.sh` OK, `uv run pytest` 163 passed, token check OK (156/32/13/0), no new warnings. No fix needed: every compile-risk spot of the M13 entry compiled as written. PR #20 "M13: per-day pipeline, live events, bench".
Bench (test-10 only, share 30 %, helper present, no ffmpeg): `bench.sh` needs a set with `bench-times.json`, so a 10-file set was made from the 10 test-10 photos (`make-bench-set.py --source local-data/bench/test-10-src --count 10 --videos 0 --out local-data/bench/test-10`; the source folder holds symlinks, originals only read). The 3,000 set was not made or run.
- per-day: wall 12.8 s, 0.78 photos/s, first day settled 2.3 s, faces 7.55 s, quality 2.43 s, places/events 2.14 s, engine peak 1,032 MB, helper 39 MB, share used 0.298.
- all-at-once: wall 7.6 s, 1.32 photos/s, faces 3.06 s, quality 2.15 s, places/events 1.70 s, engine peak 2,382 MB, helper 52 MB, share used 0.299.
- Reading: per-day is slower on 10 files over 7 days because faces start once per day (~0.65 s each, expected in `notes/m13-scale.md`); engine peak memory is less than half. The §1 budgets (3,000 set) are still not measured.
Merges into main, merge commits, each next PR retargeted to main, then `git pull` and both test suites: #15 (Swift 63, pytest 156), #16 (67, 156), #17 (74, 156), #18 (95, 157), #19 (105, 157), #20 (115, 163). All passed. Branches were not deleted.
Open: nothing was looked at in the running app (visual checklists in #16 to #20); the 3,000-file bench and the §1 budgets only when the owner asks.

### 2026-11-26 — M14a: one album, one path (Claude (Cowork))
Branch `claude/m14-album-journey` (base: M13). Owner feedback: the steps were not understandable, after adding folders
the next step was unclear, no quick way to remove albums, folders or a whole album. Design, state table, flows, what
moved where: `notes/m14a-journey.md`. Brief §12 has the IA decision.
- IA: the sidebar lists only albums (cover, name, one status line, progress ring while analysing; "+ New Album" on
  top; context menu Rename / Add Folder… / Show in Album › All Photos, Left Out / Remove Album…; ⌫ and ⌘⌫). An album
  is one path with four stations (Photos → Analysis → Questions → Album): a slim rail on top (completed stations
  reopen) and ONE primary button at the bottom ("Start", "Answer 6 questions", "Export 187 photos", "Open Folder").
  All Photos, Left Out, Favourites, Videos, Blurry, days, Moments, Chapters, People & Clocks moved to the toolbar's
  View menu. Empty state: one big New Album and a folder drop zone.
- CuratorCore `AlbumJourney.swift` (pure): `JourneyStation`, `JourneyInput` (Codable, cached per album for the
  sidebar), `JourneyAction`, `AlbumJourney` (current station, action, questions, status, labels, ring progress,
  canOpen / shown), `completedStations`, `questionsEstimate`, `removeAlbumConfirm`, `removeFolderConfirm`,
  `folderChipLabel`; plural words `.question`, `.photoObject` (SL accusative). `AlbumJourneyTests.swift`: 21 tests.
- Stations: 1 folder chips (person · camera, × with confirmation, drop / Add Folder, clocks line only asks when
  unsure); 2 the Sorting stage as is (its own Next / Resume buttons removed, the primary bar does it); 3 card stack
  "6 questions · about 2 min", primary = quick review of exactly those photos (unclear moments' frames + Have a look),
  Accept the Rest (undoable), auto-advance with "No questions: every photo was clear."; 4 cover + export inline (no
  own button; `requestExport`) + days, Done card with Export Again… and Clear Working Data….
- New Album no longer opens a wizard: it makes an empty album on station 1; the owner per folder and the album name
  come from the folders (same engine suggestion as the wizard; camera memory kept). Start begins the analysis.
  Adding folders after Start re-opens questions and the export mark. Closing the window while analysing keeps the
  app working (`AppDelegate.keepWorking`); it quits when the analysis ends with no window.
- Engine: `DELETE /api/collections/<id>/sources/<sid>` (`collections.remove_source` + `rebuild_changed_days`; rows
  only, shared content keeps its analysis and marks, no file is opened or touched, 409 while running);
  `GET …/sources` lists `devices`; `GET …/overview` has `analysis: {days, settled}`. `DELETE /api/collections/<id>`
  unchanged, now tested for thumbnails and events too.
- Motion: station change = horizontal settle + cross-fade (direction from the rail), rail pill slides
  (`matchedGeometryEffect`), station-complete check bounce + ring ≤ 0.6 s (never blocks), primary label
  `contentTransition`, sidebar ring and status roll, new album row arrives. Reduce Motion: cross-fades, check only.
- Removed (dead after the change): AlbumHome (kept `AlbumHero`, now `AlbumHero.swift`), NewAlbumWizard, StepBar and
  the step bottom bar, old Sidebar / TripPicker / FinishAlbumButton, StageLink, GuideStep, stepStates, nextStep,
  clocksWaiting, FlowPage, finishAlbumTitle/Text, finishStep / finishPeople / createAlbum / finishAlbum, AssistantSheet;
  49 strings only they used. Tests updated (GuideTests, FlowUXTests, StringsTests, LibraryModelTests: new album,
  remove folder, remove album). 96 new strings EN + SL in `// M14a journey`, no duplicates; every used key exists
  (checked with the test's own regex). Token check OK and ratcheted down: padding 156→110, cornerRadius 32→27,
  fontSystemSize 13→5, animationCurve 0.
Tests: `uv run pytest -q` 168 passed (163 + 5 new in `tests/test_m14_journey.py`, incl. a byte-snapshot check that
removing a folder and removing an album touch no source file). ExifTool installed in the container.
NOT compiled, Swift tests NOT run (Linux): run `scripts/test-mac.sh`, `scripts/build-mac-app.sh`. Compile-risk spots:
`AnyTransition.offset` inside `.asymmetric` in `motionTransition` (AlbumJourneyView); `.onChange(of: Key(...))`;
`List(selection:)` with a custom `Binding<String?>` plus `.simultaneousGesture` on rows; `.alert` with a TextField
(rename); `Section` titles inside the toolbar `Menu`; `CommandGroup(replacing: .newItem)` and
`.keyboardShortcut(.delete, modifiers: .command)`; `AppDelegate.keepWorking` + `NSApp.terminate` in `pollOnce`;
`CuratorCore.albumName(...)` qualified because `LibraryModel.albumName` shadows it; `journey` property next to
`journeyOf(_:)`; `ForEach(Array(photos.prefix(3).enumerated().reversed()), id: \.element.id)` in `CardStack`.
Visual checklist (test-10, window capture, no synthetic input; `photocurator://go?page=photos|analysis|questions|album|moments|chapters`):
1. No album: empty state with New Album and drop zone; drop `test-photos` → album arrives in the sidebar, chips show
   "Žaž · ILCE-7M4" style labels, name becomes place + dates; Start → rail moves to Analysis with the check bounce.
2. Analysis: stage full width between rail and bar; bar "Analysing · day 1 of 1", button disabled with the reason;
   sidebar ring fills; close the window → app keeps running; it quits when done (reopen from Dock first to check).
3. Questions (test-10 has one near-duplicate pair): "1 question" or more, card stack of real photos, Answer → quick
   review of only those, finishing it moves the rail to Album; Accept the Rest shows the undo toast.
4. Album: cover, export choices, primary "Export N photos" follows the Best count; export → celebration, Done card,
   primary Open Folder; sidebar "Exported" with a check.
5. Rail: click Photos / Analysis while on Album: content slides left / right, pill slides; Album not clickable before
   reached; ⌘1 … ⌘4. Reduce Motion: cross-fades only.
6. × on a chip → confirmation text, folder gone, days re-sorted, photos count drops; files in `test-photos` unchanged.
7. Sidebar ⌫ / context menu Remove Album… → confirmation text (not exported warning first), album gone, next opens.
8. View menu: All Photos, Left Out (⌘L), Moments, Chapters, People & Clocks; Esc / Back to Album returns to the path.
9. Dark and light, Increase Contrast; VoiceOver on rail stations ("2. Analysis, current") and sidebar rows.
Open: Dock reopen after closing during an analysis; ⌘⌫ inside text fields; a removed folder's cached thumbnails stay
until the album is removed (the route never touches files); `funnelParts` stays in CuratorCore without a view.

### 2026-11-26 (night) — M14a compiled on the Mac, PR #22 (Claude)
Imported `claude/m14-album-journey` from the Cowork bundle and rebased it onto main (c6f6caf). One conflict, in this log only (both sides appended an entry); main's merge entry stays first.
Results: `scripts/test-mac.sh` 132 Swift tests (122 + 10) pass, incl. `AlbumJourneyTests` (21); `scripts/build-mac-app.sh` OK; `uv run pytest` 168 passed; token check OK with the lowered baseline (110/27/5/0); no new compiler warnings. No code fix needed: every compile-risk spot of the M14a entry compiled as written.
PR #22 "M14a: one album, one path (new IA, journey, remove album/folder)", base main. Not merged (owner merges).
Open: nothing was looked at in the running app; visual checklist in #22 (empty state and drop, rail and primary button per station, questions card stack, remove folder and album with `test-photos` unchanged, View menu, close-while-analysing, light/dark, VoiceOver).

### 2026-11-26 (late night) — M14c Survey: decide a moment with every frame side by side (Claude (Cowork))
Branch `claude/m14c-survey` on M14a (#22). Owner feedback: choosing which frame to keep was not good enough; wanted
two or more photos side by side, smarter, easier, and to be told the shortcuts. Design: `notes/m14c-survey.md`
(critique, layout, decision model, the whole-app keymap table, motion, copy).
- Survey is the default for moments in the Questions station: all frames side by side at equal height (> 6: filmstrip,
  focused frame larger), recommended frame pre-selected with "Best", 1–3 reason chips per frame, a "Why" line,
  confidence pill and "Close call" (margin < 0.05: opens on the faces at 100 %), face strip per frame aligned per
  person, synced 100 % zoom (Z, hold Space, Tab cycles faces, drag pans all), progress ring "Moment 3 of 12",
  completion card that moves on by itself. Moments ordered by impact (close calls, more frames, lower margin).
- Selection: click / 1–9 only keeper, ⇧ adds, K / X on the focused frame, Return confirms (keepers stay, the rest go
  to Left Out), A accepts the suggestion, S skips, ⌫ / ⌘Z back with undo, F favourite, Esc close, ? keys. Always-visible
  shortcut bar (Survey and single review) and a one-time coach (1–9, ↩, Z, ← →).
- Multi-keep: the engine stores one keeper per moment, so the first keeper (the recommended one when kept) is the
  engine keeper (`keep(group:photo:)`), the other keepers get `keep = true` ("keep too"), the rest `rejected = true`.
  Back restores every frame's marks and the earlier keeper (`applySurvey` / `undoSurvey`).
- Single review: K / X aliases, the shortcut bar; C opens Survey for the photo's moment. Clock questions unchanged.
  Moments page: "Survey" opens Survey from the selected moment on.
- Removed: `CompareView`, `CompareSession`, the compare keymap context and commands, 12 strings only they used,
  `questionIds()` (now `questions()`), `compareRequest` / `startCompare` (now `surveyRequest` / `startSurvey`).
- CuratorCore: `Survey.swift` (new), `ReviewKeymap.swift` (`.survey`, `KeyAction`, `bar`, `coach`, key codes),
  `ReviewZoom.swift` (compare session removed), `Automation.swift` (keys `confirm`, `accept`), 61 strings EN + SL at
  the end under `// M14c survey` (no duplicates; every used key exists, checked with the test's regex).
- Tests: new `SurveyTests.swift` (14: engine moment and confidence, moment from photos, impact order, pick / ⇧ toggle,
  focus / K / X / Tab, confirm with multi-keep, primary rule, accept, back over skip and decision, finished safety,
  chips, face columns and Tab target, layout, coach); `ReviewKeymapTests` updated (K / X in single, Survey keys,
  ⇧ digits, key codes, bar and coach consistent with the card; compare tests removed).
- Token check OK, unchanged (110 / 27 / 5 / 0). Python untouched (another agent works on SortingStage, Thumbnails and
  Python in parallel; none of those files were edited).
NOT compiled, Swift tests NOT run (Linux): run `scripts/test-mac.sh`, `scripts/build-mac-app.sh`. Compile-risk spots:
`onKeyPress(phases: [.down, .up])` with `press.phase == .up` and `KeyEquivalent.tab` (Tab may go to the focus system
first); `NSApp.currentEvent?.keyCode` inside `onKeyPress`; `let cells = ForEach(...)` reused in two branches of a
`@ViewBuilder` func (SurveyView.row); `.motionTransition(.asymmetric(insertion: .offset(x:).combined(with:), removal:
.identity))`; `.accessibilityAddTraits(focused ? [.isImage, .isSelected] : .isImage)`; `withMotion { e = session.back() }`
assigning a captured local; `ActiveSurvey` (non-Equatable) in `@State`; `SurveyFrame.ratio` passed to `map`;
`Text(...).monospaced()`; `ShortcutBar` / `KeysCard` names; `[Int: [String: MarkValue]]` comparisons in tests.
Visual checklist (test-10 has one near-duplicate pair; window capture, no synthetic input;
`photocurator://go?page=questions`, then `key?k=pick1|pick2|confirm|accept|back|zoom|unzoom|esc`):
1. Answer questions → Survey: both frames side by side, equal height, "Best" on the recommended one, chips under each,
   face strip with eye rings; coach card on first open only (gone after any key; `defaults delete si.beehive.photocurator surveyCoachSeen.v1` to see it again).
2. 1 / 2 move the green ✓ and ring; ⇧2 adds (tally "2 kept · 0 to Left Out"); X on the focused frame → "Nothing kept"
   in orange.
3. Z: both frames at 100 % on the same face, drag pans both; hold Space zooms, release returns; Tab rings the next
   person (needs a moment with two faces).
4. Return: keepers lift, others drop, next moment slides in; on the last one the completion card shows, then the
   path moves to Album (or to the Have a look photos first). ⌫ during the card goes back.
5. Left Out view lists the frames left out; put one back; Back in Survey restores marks and keeper (engine reload).
6. Single review: bar at the bottom, K / X work, C opens Survey for a moment frame and Esc returns to the photo.
7. Moments page "Survey" button opens from the selected moment; Esc closes back to the page.
8. Reduce Motion: cross-fades only, no sink / bounce; VoiceOver reads "Frame 1 of 2: …, Best, Keep"; light and dark.
9. A moment with 7+ frames (full 236-photo set only with the owner's OK): filmstrip, focused frame larger, scrolls.
Open: Smiling / Horizon chips need engine fields; up to six originals decode at 100 % when zoomed; a moment with nothing
kept keeps its engine keeper (all frames rejected) until the question review finishes.

### 2026-11-26 (late) — M14c: Analysis station fixes from the owner's screenshot (Claude (Cowork))
Branch `claude/m14c-stage-fixes` (base: M14a PR #22). Screenshot: album "Tuscany, 22–28 Oct 2026", 236 photos, 3 folders.
Root causes and fixes:
1. All photos under "No date", "day 1 of 1": not the day plan (it runs after clocks). The app last fetched the photos
   while the folders were read (photo count changed), before `resolve_all` wrote any capture time, and fetched them
   again only on the first event, after clocks + places + events; the overview counted the untimed photos as one
   "unknown" day. Fix: engine phase plan (below); the app reloads photos (and overview) when the phase moves to
   clocks / places / days (`reloadsPhotos`, `LibraryModel.pollOnce`); `_analysis_days` answers 0 days while any photo
   has no capture time (`app/assistant.py`).
2. Tiles over the trays: `stageFlow` grew past the rect below 28 pt and the grid fallback only applied once settled;
   every row also reserved the day-label band. Fix: label band only on rows where a day begins, gaps shrink with small
   tiles, `StageFlow.fits`; the stage uses the clipped scrolling grid whenever the flow does not fit (running too),
   and the stage model goes instant then (`StageModel.overflowing`).
3. Chips: the New Album suggestion takes the person from EXIF Artist (a hired photographer's name in every file) and
   the stage chip showed only that name; "…" was the only state for "no count". Fix: `app/source_chips.py`
   (`pretty_device`: "Sony A7 IV"; `chip_labels`: person · camera, folder name on a clash, then a number; a folder
   name used as the person is not shown as a person; `source_state`: waiting / reading n of m / read / empty / failed
   with reason); `/sources` returns `chip`, `read_state`, pretty `devices`; the app shows them (stage chip, folder
   chips, remove confirmation) with an older-engine fallback (`sourceChipName`, `sourceChipDetail`).
   Not known: why "Toskana 2026" had 0 photos in the stage on the Mac; the chip now says which state it is in.
4./5. "Aligning clocks 100%" next to "Working": two readings of the status text (the stage had no title for the
   clocks phase) and a progress that was the last stage's share (100 % left over into day 1). Fix:
   `app/analysis_progress.py` `PhasePlan` (reading → clocks → places → days (step) → finishing, fixed shares, never
   goes back), job status `stage`; CuratorCore `AnalysisStatus.swift` (`analysisStatus`, `analysisTitle` "Reading
   photos / Aligning cameras / Finding places / Sorting day 3 of 7 / Comparing similar shots", `analysisDetail`,
   `activityFraction`). Stage header, toolbar pill and `AnalysisCard` read it; the pill hides while the Analysis
   station shows the album being analysed.
6. Polish: the tile the engine is at (day N, step counter) gets the scan band plus a lit edge (`analysing`), day
   headers light up with a check and one glow when `settled_day` arrives (`StageDayLabel`, grid too, also above 400),
   subtitle and counters roll (numericText); Motion tokens only, Reduce Motion = lit/check without movement, overlays
   do not take hits; shimmer off when instant (skipped, > 400, or overflowing).
Python: `uv run pytest -q` 177 passed (168 + 9 in `tests/test_m14c_stage.py`: real days at the first clocks/places
report with a 4-day, 3-folder fixture incl. just-after-midnight photos, overview 0 days while reading, phase order and
monotonic progress, PhasePlan unit, job `stage`, device names, chip labels, chip states, `/sources` chip + state).
`tests/conftest.py`: `make=` option for the fake EXIF (default unchanged). Token check OK (baseline lowered 110→108,
27→26).
Swift NOT compiled, Swift tests NOT run (Linux). New: `CuratorCore/AnalysisStatus.swift`,
`Tests/CuratorCoreTests/M14cStageTests.swift` (11). Compile-risk spots: `Cell` struct local to the nested func in
`stageFlow`; `try? c.decodeIfPresent` for `JobStatus.stage` / `SourceInfo.readState` (optional flattening);
`SourceInfo` now has an explicit `init(from:)`; `JobStatus.init` gained `kind:`/`stage:` defaults; `AnalysisPhase`
`Comparable` via `allCases.firstIndex`; `StageTile` memberwise order (`analysing` after `scanning`); `StageGrid`
memberwise with `settledDays` before the trailing `open` closure; `ActivityPill` body wrapped in `Group { if … }` with
`.popover` inside; `.symbolBounce(on: Bool)`; `StageModel.setOverflowing` called from the grid's `onAppear`.
Visual checklist (test-10 and, with the owner's OK, the 236-photo folder; no synthetic input):
1. While reading: chips say "Waiting" / "Reading 12 of 80", names distinct; header "Reading photos", one bar.
2. When clocks start: photos regroup under real days at once; sidebar never says "day 1 of 1".
3. Header "Aligning cameras" → "Finding places" → "Sorting day 3 of 7" / "Comparing similar shots"; bar only grows;
   no toolbar pill on the Analysis station; pill shows the same words on another view.
4. 236 photos in a small window: tiles never over the trays (flow shrinks or the clipped grid scrolls); > 400 grid.
5. A lit edge + band on one tile per moment, moving through the day; day header turns bright with a check per
   settled day; Reduce Motion: no band movement, no bounce; clicks on tiles still work during it.
6. Folder chips on the Photos station and the remove confirmation use the same names.
Open: why the third folder had no photos on the Mac; StepPhotos (People & Clocks) cards still show the raw owner.

### 2026-11-26, Claude (Cowork): M14c = Survey + stage fixes merged
- `claude/m14c-survey` now holds both halves: Survey (multi-frame decisions, synced zoom, one keymap, shortcut bar, coach) and the stage fixes (real days instead of "No date", no overlap with trays, distinct source chips, one phase status, stage polish). Conflicts only in appended blocks (Strings: 660 keys, no duplicates; log). Token check OK (108/26/5/0). pytest on the stage branch: 177 passed.
- Not compiled. Both halves' compile-risk spots are in their own entries above.

### 2026-11-26 (night, later) — M14c compiled on the Mac, PR #23 (Claude)
Imported `claude/m14c-survey` from the Cowork bundle. #22 had no new commits on GitHub, so no rebase (the branch already sits on its tip a6bc0ca).
Fix: `SurveyTests.swift` had a single-line raw string `#"…"#` split over two lines (unterminated literal); now a multi-line raw string `#"""…"""#`, same JSON. The only compile error; every risk spot of both M14c entries compiled as written.
Results: `scripts/test-mac.sh` 155 Swift tests (145 + 10) pass, incl. `SurveyTests` (14) and `M14cStageTests` (11); `scripts/build-mac-app.sh` OK; `uv run pytest` 177 passed; token check OK (108/26/5/0); no new compiler warnings compared with #22.
PR #23 "M14c: Survey (multi-frame decisions) + analysis stage fixes", base `claude/m14-album-journey`. Not merged (owner merges; #22 first).
Open: nothing was looked at in the running app; visual checklists (Survey and Analysis station) in #23.

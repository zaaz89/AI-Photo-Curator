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

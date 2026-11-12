# AI Photo Curator
## Complete Project Brief, Technical Specification & Development Instructions

**Document status:** Living document and source of truth for scope. Last updated 2026-11-12. When a decision changes the scope, update this file in the same PR and record the reason in `project-log.md`.

**Project type:** Personal AI-powered photo management application  
**Target platform:** macOS, Apple Silicon  
**Development approach:** Fork and extend an existing open-source project  
**Base repository:** https://github.com/kotyzap/Photo-Curator  
**Original project version:** v7.0 at the time of initial review (upstream commit `1cb56a0`)  
**License:** MIT  
**Commercial intent:** None. Private, personal use only.  
**Primary development environment:** MacBook Pro, Apple Silicon M5 Pro  
**Development assistants:** OpenAI Codex (ChatGPT) and Claude Code both work on this repository. Collaboration rules are in `AGENTS.md`.  
**Primary language:** English for code and documentation. The interface should eventually support English and Slovenian.

---

# 1. PROJECT VISION

Build an intelligent, privacy-first, local AI photo organizer that can automatically analyze, understand, deduplicate, rank, chronologically organize, rename and export photos and videos collected from multiple people and devices.

The primary use case is combining thousands of travel photos captured independently by two people into one accurately ordered, intelligently organized collection.

The application should significantly reduce manual photo management while preserving original image quality, metadata, file integrity and meaningful memories.

The desired result should be more useful for personal travel photography than a conventional duplicate cleaner or photo culling application.

**Core principle:**

> Import a messy collection of thousands of photos from different devices and people, and transform it into one clean, chronological, intelligently labeled and curated travel collection with minimal manual effort.

The application must never silently delete, overwrite, move or modify original files.

AI should make recommendations and explain uncertainty, not make irreversible decisions.

---

# 2. EXISTING OPEN-SOURCE FOUNDATION

## 2.1 Repository

https://github.com/kotyzap/Photo-Curator

This repository is the owner's GitHub fork: https://github.com/zaaz89/AI-Photo-Curator (forked at upstream v7.0, commit `1cb56a0`). Git remote `origin` is the fork, `upstream` is the original project. Do not create another fork or a parallel repository.

The fork is public on GitHub. Never commit personal photos, databases, location data or credentials.

Before implementing changes, inspect the entire current repository and confirm its actual capabilities, implementation, compatibility and security properties.

Do not assume that every documented feature is correctly implemented.

The existing application uses Python and Flask with a browser-based local interface.

The reviewed version already includes:

- JPEG and PNG support
- HEIC/HEIF support using pillow-heif
- RAW image support using rawpy
- EXIF metadata extraction
- GPS location display
- Image sharpness analysis
- Perceptual image hashing
- ORB-based similarity confirmation
- Near-duplicate clustering
- Image quality ranking
- Photo culling workflow
- Local thumbnail generation
- Browser-based photo inspection
- Export functionality

The existing processing workflow is:

**Cull → Deduplicate → Rank**

Preserve useful existing functionality while improving the architecture.

## 2.2 Existing files identified

The repository includes:

- `photo_curator.py`
- `photo_dedup_batch.py`
- `photo_file_organizer.py`
- `photo_ranking_engine.py`
- `photo_ranking_v3.py`
- `raw_loader.py`
- `requirements.txt`
- `README.md`
- `SECURITY.md`
- `LICENSE`

The upstream `docs/` folder is the original project's landing page (HTML, screenshots, old zip bundles), not project documentation for this fork.

The main application script is relatively large, so evaluate whether the architecture should be progressively modularized.

## 2.3 Important findings from the initial code review

The current organizer uses filesystem move operations for blurry and duplicate photos.

Some operations may create directories even in dry-run mode.

This is unacceptable for the intended default workflow.

Implement a truly read-only analysis and preview system.

Decision 2026-11-12: all features that move original files (tier toggle relocation, dedup auto-move, "Move blurry") are removed from the fork. Selection becomes marks only; files leave the source only as verified copies in an export. Details: `notes/phase-0-audit.md`.

Exports must use a separate destination and preserve original files.

The existing repository's documentation describes local execution and security protections. These claims must be verified against implementation and tests.

## 2.4 License

The repository uses the MIT license.

Retain the original copyright and license notices in the fork.

Review the licenses of all additional libraries, models, weights and bundled components before integration.

---

# 3. TARGET USER WORKFLOW

The ideal workflow should be extremely simple.

### Step 1: Create project

User creates a new collection.

Example:

`Tuscany Trip 2026`

Optional metadata:

- Trip name
- Date range
- Country
- Participants
- Main destination
- Output directory

These details should help the AI but must not override the actual photographic evidence.

### Step 2: Import photos

The user imports photos from multiple sources.

Example:

Source A: My iPhone photos  
Source B: Partner's iPhone photos  
Source C: Google Drive folder  
Source D: Additional camera or exported archive

The application should accept multiple folders in one collection.

It must remember which source each file came from.

### Step 3: Analyze metadata

Extract relevant information from every image and video.

### Step 4: Build unified timeline

Merge photos from different devices into a single chronological timeline.

Identify possible clock synchronization issues.

### Step 5: Analyze visual content

Understand subjects, scenes, locations and similarities.

### Step 6: Detect duplicates

Group identical and nearly identical photos.

### Step 7: Rank photos

Recommend the best photos within similar groups.

### Step 8: Organize events

Automatically group photographs by day, location and event.

### Step 9: Review recommendations

Display a clear review interface.

Allow the user to accept, reject or customize suggestions.

### Step 10: Export

Generate a clean folder structure with intelligently named files.

Verify all exported files.

Preserve original files.

---

# 4. MULTI-DEVICE AND MULTI-PERSON SUPPORT

This is one of the project's most important features.

Two people may photograph the same event independently.

Their files may have:

- Different filenames
- Different capture times
- Different time zones
- Different camera settings
- Different image resolutions
- Different formats
- Slightly different GPS coordinates
- Different image compositions
- Different device clock offsets

The application must merge these into a consistent chronological collection.

## 4.1 Source identity

Every imported file should store:

- Source folder
- Source owner
- Device identity, if available
- Original filename
- Original path
- Import date
- File checksum
- Original metadata
- Derived metadata
- Processing state

Source owners should be user-editable.

Example:

Owner 1: Person A  
Owner 2: Person B

Do not infer ownership solely from the presence of a person in a photograph.

## 4.2 Chronological ordering

Use available metadata to determine the most trustworthy capture timestamp.

Potential fields:

- EXIF DateTimeOriginal
- EXIF SubSecTimeOriginal
- EXIF OffsetTimeOriginal
- QuickTime creation date
- GPS date and time
- Google Takeout metadata
- Filename timestamps
- Filesystem timestamps

Preserve the original metadata values.

Create a separate normalized UTC capture timestamp where justified.

Track timezone assumptions and confidence.

Avoid using file modification timestamps as the primary capture timestamp when reliable capture metadata exists.

If the true capture time cannot be established, mark it as uncertain.

Do not silently invent timestamps.

## 4.3 Clock synchronization

Implement optional detection of device clock offsets.

Example:

Person A captures a photograph at 18:14:32.

Person B captures a visually matching scene with a timestamp of 18:12:48.

The application should investigate whether the difference is caused by:

- Two photographs taken at different moments
- Device clock drift
- Timezone interpretation
- Incorrect timestamp metadata
- Import/export metadata alterations

Use overlapping GPS tracks, visually matching sequences and multiple independent reference points where possible.

Never infer a global clock correction from a single loosely similar image.

Show the user a proposed correction with supporting evidence and confidence.

All corrections must be reversible and stored separately from original metadata.

---

# 5. DUPLICATE DETECTION

Build a multi-layer duplicate detection pipeline.

## 5.1 Exact duplicates

Use cryptographic checksums such as SHA-256.

Identical hashes indicate identical file contents.

## 5.2 Near-identical photos

Use perceptual hashing and image similarity techniques.

Examples:

- Burst photos
- Slight exposure changes
- Recompressed files
- Cropped versions
- Images captured seconds apart

Potential techniques:

- pHash or dHash
- Existing perceptual hashing implementation
- ORB matching
- Image embeddings
- Temporal proximity
- GPS proximity

## 5.3 Same event, different photographs

Do not classify all images of the same subject as duplicates.

Example:

Two people photograph the same sunset from slightly different positions.

Both images may be worth keeping.

Distinguish:

1. Exact duplicate
2. Near duplicate
3. Similar scene
4. Same event but distinct image

Only the first two categories should normally produce removal recommendations.

Even then, deletion must never occur automatically.

## 5.4 Best photo selection

The system should recommend a preferred image within each duplicate group.

Consider:

- Sharpness
- Resolution
- Exposure
- Noise
- Composition
- Subject visibility
- Facial quality
- Closed eyes
- Motion blur
- Image artifacts
- Overall aesthetic score

Do not always select the largest file or sharpest image.

A slightly less sharp but emotionally meaningful image may be preferable.

Provide user controls to override AI choices.

---

# 6. AI VISUAL UNDERSTANDING

Integrate local AI models capable of understanding photograph contents.

The objective is semantic understanding, not merely similarity detection.

Potential capabilities:

- Identify landscapes
- Recognize architecture
- Identify food and drinks
- Identify animals
- Recognize beaches, mountains, lakes and forests
- Identify city scenes
- Describe activities
- Recognize common photographic subjects
- Identify recognizable landmarks when evidence is sufficient
- Generate short image descriptions
- Suggest relevant tags
- Support semantic photo search

Examples:

"Show me all photos with sunset views."

"Find pictures of us in restaurants."

"Show the best pictures from Florence."

"Find photos of the same cathedral."

"Show all photos taken in the evening."

## 6.1 Recommended AI approach

Use multiple specialized methods rather than relying on a single language model.

Potential components:

**Image embeddings**

Use CLIP, SigLIP or a suitable modern alternative for semantic similarity and retrieval.

**Vision language model**

Use an efficient locally executable vision model through Ollama or another reliable local runtime.

**Image quality analysis**

Reuse or improve the existing quality-ranking pipeline.

**Face analysis**

Use a local face detection and embedding system where appropriate.

**GPS and metadata intelligence**

Combine visual understanding with physical location and timestamp metadata.

## 6.2 Confidence handling

AI must not fabricate specific locations, people or events.

For example, a photograph of an Italian village should not automatically be identified as Pienza without sufficient evidence.

Use:

- GPS proximity
- Timestamp
- Trip context
- Landmark evidence
- Visual similarity
- Neighboring images

Store confidence and provenance.

If uncertain, generate a generic description instead of a falsely specific one.

---

# 7. EVENT DETECTION AND SMART GROUPING

Automatically identify meaningful photographic events.

Potential event categories:

- City walk
- Restaurant visit
- Sunset
- Museum visit
- Hiking
- Hotel stay
- Scenic viewpoint
- Beach visit
- Road trip
- Landmark visit

Combine:

- Time intervals
- GPS clustering
- Visual similarity
- Semantic embeddings
- Context from surrounding photos

Example output:

Tuscany Trip 2026

October 23

- Morning in Pienza
- Walking through the historic center
- Sunset in Val d'Orcia
- Dinner

October 25

- Siena city center
- Piazza del Campo

October 28

- Florence sightseeing
- Cathedral
- Ponte Vecchio

These are illustrative examples only.

Actual events must be determined from imported files.

User should be able to:

- Rename events
- Merge events
- Split events
- Move photos between events
- Correct locations
- Correct timeline ordering

Do not automatically discard photos simply because they do not fit a detected event.

---

# 8. SMART FILE NAMING

Implement intelligent and deterministic file naming.

Recommended naming pattern:

`YYYY-MM-DD_HH-MM-SS_Location_Event_Sequence.extension`

Example:

`2026-10-23_18-14-32_Pienza_Sunset_001.HEIC`

Other naming templates should be supported.

Examples:

`YYYYMMDD_HHMMSS_OriginalName`

`YYYY-MM-DD_Location_Sequence`

`TripName_Day_Event_Sequence`

Requirements:

- Preserve extensions
- Preserve the original file contents
- Avoid filename collisions
- Handle missing dates and locations
- Support Unicode filenames
- Sanitize invalid filename characters
- Preserve original filename in the database
- Support a reversible rename/export manifest

For files without trustworthy capture times, use a clearly documented fallback rather than a fabricated date.

AI descriptions should be concise and should not introduce unverified details.

---

# 9. FOLDER ORGANIZATION

Support customizable folder structures.

Default proposal:

Tuscany 2026/
- 2026-10-22/
- 2026-10-23_Pienza/
- 2026-10-24_Val_d_Orcia/
- 2026-10-25_Siena/
- 2026-10-28_Florence/

Alternative modes:

**Chronological**

Trip / Date / Images

**Location-based**

Trip / Country / City / Images

**Event-based**

Trip / Date / Event / Images

**Flat chronological**

One folder, every file renamed with chronological prefixes.

**Curated**

Separate output collections for selected photos and reviewed alternatives.

Folder structures must be generated from verified data and user-approved event labels.

Preserve chronological order within each folder.

---

# 10. GOOGLE INTEGRATIONS

## 10.1 Google Drive

Initially support Google Drive through locally synchronized folders.

The user can download or sync a Google Drive folder to the Mac.

The application should then index it like any other local source.

Do not require Google OAuth in the first version.

Avoid mutating synchronized source folders.

## 10.2 Google Photos

Support Google Photos as a future integration.

Google Photos Library API access has significant restrictions for existing user libraries.

Investigate current official API capabilities before implementation.

Potential approaches:

**Google Photos Picker API**

Allow users to explicitly select photographs for import.

**Google Takeout**

Import exported Google Photos archives.

Handle sidecar JSON metadata where available.

**Manual local export**

Allow user-selected image archives or folders.

Do not promise automatic unrestricted access to the entire Google Photos library.

Do not implement unsupported remote deletion.

## 10.3 Long-term direction

Potentially support:

- Google Drive
- Google Photos
- Apple Photos exports
- Local directories
- External drives
- SD cards

All import methods should feed the same internal indexing pipeline.

---

# 11. VIDEO AND LIVE PHOTO SUPPORT

The application should eventually support:

- MP4
- MOV
- Smartphone video recordings
- Apple Live Photos
- HEVC video
- Embedded video metadata

Apple Live Photos may contain a still image and a separate video component.

These must remain logically associated.

Never remove a Live Photo video merely because its still image appears similar to another image.

Capture timestamps and metadata may differ between stills and video files.

The importer should detect and reconcile those relationships.

Video deduplication and semantic video analysis can be implemented in later phases.

However, the initial importer must avoid corrupting or unintentionally separating paired assets.

---

# 12. USER INTERFACE

The application should look and feel like a polished modern macOS photo utility.

Avoid an overly technical or complicated interface.

Design goals:

- Fast
- Minimal
- Responsive
- Clear visual hierarchy
- Large image previews
- Excellent thumbnail performance
- Dark and light modes
- Simple actions
- Transparent AI recommendations

## 12.1 Main navigation

Suggested sections:

**Dashboard**

Overview of imported collections.

**Library**

All photos with filtering and search.

**Timeline**

Unified chronological view across all devices.

**Duplicates**

Exact and near duplicate groups.

**AI Suggestions**

Recommended photos, detected events and suggested improvements.

**People & Sources**

Source device and photo ownership management.

**Export**

Preview, naming rules, folder structure and execution.

**Settings**

AI model selection, performance, privacy and defaults.

## 12.2 Photo detail screen

Display:

- Full-resolution preview
- Original filename
- Capture date and time
- Source owner
- Camera model
- GPS coordinates
- Location
- File size
- Resolution
- AI tags
- AI description
- Quality score
- Similar images
- Duplicate status
- Confidence indicators

## 12.3 Duplicate review

Use side-by-side comparison.

Clearly identify:

- Recommended keeper
- Alternative shots
- Reasons for recommendation
- Similarity level
- Quality metrics
- Selected actions

Allow keyboard shortcuts for efficient review.

## 12.4 Progress tracking

Show processing stages and real progress.

Examples:

- Importing
- Extracting metadata
- Creating thumbnails
- Detecting duplicates
- Generating embeddings
- Analyzing scenes
- Building timeline
- Preparing export

Users should be able to cancel and resume long-running operations.

---

# 13. TECHNICAL ARCHITECTURE

## 13.1 Preserve the existing backend initially

Keep the existing Python processing engine as the initial foundation.

Avoid a complete rewrite unless the repository audit establishes a clear technical reason.

## 13.2 Proposed stack

| Layer | Proposed technology |
|---|---|
| Existing backend | Python |
| Initial API | Flask |
| Database | SQLite |
| Metadata | ExifTool (required, Homebrew; batch JSON), Pillow EXIF as fallback |
| Image processing | Pillow, OpenCV |
| HEIC | pillow-heif |
| RAW | rawpy |
| Exact duplicate detection | SHA-256 |
| Near duplicate detection | Existing perceptual hash + ORB |
| Semantic image retrieval | SigLIP 2 base (`google/siglip2-base-patch16-224`, decided 2026-11-12) |
| Local vision AI | Ollama with `qwen3-vl:4b` (decided 2026-11-12; models stored in `local-data/models/`) |
| Face detection | Apple Vision or suitable local model |
| Background processing | Python workers |
| Frontend | Existing interface initially |
| Future frontend | React + TypeScript |
| Future desktop packaging | Tauri, if justified |
| Testing | pytest |
| Target hardware | Apple Silicon |

Do not assume a specific local model will run efficiently without benchmarking it.

Prefer Apple Silicon and Metal acceleration when available.

## 13.3 Proposed modules

Refactor incrementally into independent components.

Suggested structure:

```text
ai-photo-curator/
  app/
    api/
    database/
    importers/
      local_importer.py
      google_takeout_importer.py
    metadata/
      exif_reader.py
      timestamp_resolver.py
      gps_resolver.py
    timeline/
      timeline_engine.py
      clock_sync.py
      event_detector.py
    duplicates/
      exact_duplicates.py
      visual_duplicates.py
      semantic_groups.py
    ai/
      embeddings.py
      vision_analyzer.py
      quality_ranker.py
      face_analyzer.py
    organization/
      naming_engine.py
      folder_engine.py
      export_engine.py
    safety/
      file_verification.py
      operation_manifest.py
    models/
    services/
  frontend/
  tests/
  docs/
  README.md
```

This is a target architecture, not an instruction to immediately move or rewrite all existing files.

Preserve compatibility during migration.

---

# 14. DATABASE DESIGN

Use SQLite for persistent indexing and processing state.

Storage location (decision 2026-11-12): all collection data (database, thumbnails, caches, logs) lives in `local-data/collections/<id>/` inside the project folder, which git ignores. Nothing is ever written inside a source folder.

Suggested entities:

**Collections**

Trip or photo collection information.

**Sources**

Imported folders, people, devices and origin details.

**MediaAssets**

Original file identity, format, path, checksum and ownership.

**Metadata**

Original and normalized timestamps, camera information, GPS and other extracted properties.

**AssetRelationships**

Live Photo pairs, RAW/JPEG pairs and related media assets.

**ImageEmbeddings**

Cached semantic representations.

**DuplicateGroups**

Clusters of identical and near-identical assets.

**Events**

Detected chronological and geographic groupings.

**AIAnnotations**

Generated descriptions, classifications and confidence.

**UserDecisions**

Accepted, rejected and overridden suggestions.

**ExportJobs**

Output configuration and execution state.

**OperationManifest**

Audit trail of all planned and completed filesystem operations.

Key requirements:

- Incremental indexing
- Cached results
- Schema migrations
- Repeatable processing
- Reversible user decisions
- Safe reimport
- No accidental duplicate database records
- Original and derived metadata stored separately

---

# 15. PRIVACY AND SECURITY

This is a private personal application.

Default behavior should be local-first.

Requirements:

1. No automatic uploads of photos to external AI providers.
2. No telemetry by default.
3. No advertising or analytics SDKs.
4. No automatic cloud synchronization.
5. No destructive operations without explicit approval.
6. Clear distinction between source and export folders.
7. Restrict local API filesystem access.
8. Validate file paths and symlinks.
9. Protect against unsafe filenames.
10. Restrict any local server to loopback.
11. Review dependencies and vulnerabilities.
12. Store credentials securely if cloud integrations are introduced.

Local AI should be preferred.

Any optional external AI integration must require explicit opt-in and clearly indicate which image data will leave the device.

---

# 16. FILE SAFETY REQUIREMENTS

File safety is a top priority.

The application must never silently:

- Delete original files
- Overwrite source files
- Alter EXIF metadata
- Convert HEIC originals into JPEG
- Reduce original image resolution
- Discard Live Photo video components
- Move original files into other folders
- Replace originals with compressed copies

Default workflow:

**Index → Analyze → Recommend → Preview → Export copies → Verify**

Implement a genuine dry-run mode that performs no filesystem mutations.

Before executing an export:

- Check destination availability
- Detect naming collisions
- Check available disk space
- Validate output paths
- Generate an operation manifest

After export:

- Verify copied contents using checksums
- Validate the exported file count
- Record failures and skipped files
- Preserve a complete operation log

Support restarting interrupted exports.

Never claim an export succeeded until verification has completed.

---

# 17. PERFORMANCE

Optimize for thousands to tens of thousands of photos.

Important requirements:

- Incremental processing
- Persistent thumbnail cache
- Embedding cache
- Metadata cache
- Batch AI inference
- Background workers
- Memory-aware processing
- Efficient similarity search
- Avoid redundant rescanning
- Avoid reprocessing unchanged files

Use a staged processing pipeline.

Example:

1. Lightweight metadata scan
2. Exact duplicate detection
3. Thumbnail generation
4. Near-duplicate analysis
5. Semantic embeddings
6. Vision LLM analysis for selected assets
7. Event grouping
8. Export preparation

Do not run an expensive vision language model on every image unless it is necessary.

Prefer inexpensive filtering and embeddings before detailed AI analysis.

Benchmark using actual Apple Silicon hardware and realistic travel collections.

---

# 18. DEVELOPMENT ROADMAP

## Phase 0: Repository audit

Before implementation:

- Clone or fork the repository
- Inspect the codebase
- Confirm dependency compatibility
- Run the existing app
- Establish baseline behavior
- Identify unsafe filesystem operations
- Inspect code organization
- Identify missing test coverage
- Review security
- Create an implementation plan

Deliverable:

Technical audit and prioritized roadmap.

## Phase 1: Reliable multi-source indexing

Implement:

- Collection creation
- Multiple local folder imports
- Source ownership
- EXIF extraction improvements
- Normalized capture timestamps
- SQLite indexing
- Basic combined chronology
- Non-destructive preview

Deliverable:

Photos from two devices displayed together in chronological order.

## Phase 2: Smart duplicates and ranking

Improve:

- Exact duplicate detection
- Near-duplicate detection
- Group review
- Best photo recommendations
- User override controls
- Preserve useful alternative perspectives

Deliverable:

Clear and reliable recommendations on which photos to keep.

## Phase 3: AI understanding

Implement:

- Local semantic embeddings
- Vision model integration
- AI descriptions
- Intelligent tags
- Semantic search
- Confidence tracking

Deliverable:

Application understands and categorizes photo contents.

## Phase 4: Smart timeline and events

Implement:

- Automatic event clustering
- GPS-based location grouping
- Multi-device timestamp analysis
- Clock offset suggestions
- Event naming
- User corrections

Deliverable:

Unified travel timeline organized by meaningful events.

## Phase 5: Smart export

Implement:

- Naming templates
- Location-aware names
- Date and event folders
- Export preview
- Copy verification
- Reversible operation manifest

Deliverable:

Fully organized export suitable for Google Drive or local archival.

## Phase 6: UI modernization

Improve:

- Dashboard
- Timeline interface
- Duplicate comparison
- AI suggestions
- Metadata inspection
- Keyboard navigation
- Visual consistency
- Performance

Deliverable:

Polished macOS user experience.

## Phase 7: Advanced integrations

Potential features:

- Google Photos Picker
- Google Takeout import
- Apple Photos exports
- Face recognition and grouping
- Advanced video support
- Smart travel highlights
- Automatic slideshow generation

These must not delay the core MVP.

---

# 19. ACCEPTANCE CRITERIA

The initial production-quality version must satisfy the following:

### Import

- Import from two or more local folders.
- Preserve source identity.
- Support common iPhone image formats.
- Handle filenames that collide across devices.
- Avoid modifying source files.

### Timeline

- Correctly order photos using reliable timestamps.
- Support images from multiple devices.
- Handle missing and inconsistent metadata.
- Display uncertainty rather than guessing.
- Allow manual correction of clock offsets.

### Duplicates

- Reliably identify byte-identical images.
- Detect visually near-identical images.
- Avoid grouping clearly distinct photos as disposable duplicates.
- Allow manual override.
- Never auto-delete.

### AI

- Generate useful semantic descriptions.
- Identify common subjects.
- Support semantic grouping.
- Combine AI inference with actual metadata.
- Avoid presenting guesses as verified facts.

### Organization

- Group photos chronologically.
- Suggest meaningful event groupings.
- Create deterministic filenames.
- Avoid filename collisions.
- Allow manual edits before export.

### Export

- Preserve original image data.
- Preserve metadata by copying original bytes.
- Generate a complete operation manifest.
- Verify output integrity.
- Never modify originals.

### Reliability

- Recover from partial processing failures.
- Resume interrupted analysis.
- Cache completed work.
- Handle corrupt or unsupported media gracefully.
- Never claim an operation succeeded when it failed.

---

# 20. TESTING STRATEGY

Create automated tests and a representative real-world test dataset.

The test dataset should include:

- Photos from two different phones
- JPEG and HEIC
- Identical files
- Near-identical images
- Burst sequences
- Different photos of the same event
- Incorrect timestamps
- Missing GPS
- Missing EXIF
- Duplicate filenames
- Daylight saving time transitions
- Photos from different time zones
- Images copied through cloud storage
- Live Photos
- RAW/JPEG pairs
- Corrupted files

Test deterministic processing with known expected results.

Validate:

- File integrity
- Metadata accuracy
- Timeline accuracy
- Duplicate grouping quality
- False-positive rates
- Export naming consistency
- Processing stability
- Non-destructive behavior

AI quality should be evaluated using manually labeled reference examples rather than relying entirely on subjective impressions.

Real personal photos used for testing stay outside git (see `.gitignore`, folder `local-data/`).

First real test set (2026-11-12): `~/Desktop/photos` on the owner's Mac. It is a source folder: read only, never write into it. 236 Lightroom-exported JPEGs from two Sony cameras at one event; no GPS, HEIC, Live Photos or video. Description in `notes/phase-0-audit.md`, section 10.

---

# 21. DEVELOPMENT RULES FOR THE AI AGENT

Follow these principles throughout development.

**1. Inspect before changing.**

Never assume existing behavior from filenames or documentation alone.

**2. Reuse existing functionality.**

Avoid unnecessary rewrites.

**3. Prioritize core processing over visual polish.**

First make the results correct, then improve the interface.

**4. Protect original data.**

No destructive operation may be introduced without explicit approval.

**5. Implement incrementally.**

Work in small, testable milestones.

**6. Maintain modularity.**

Avoid adding substantial new functionality to the existing monolithic application file.

**7. Keep AI optional and replaceable.**

Do not tightly couple the app to a single model provider.

**8. Prefer local processing.**

Privacy and minimal operating costs are important.

**9. Handle uncertainty.**

Do not fabricate locations, timestamps, identities or events.

**10. Verify every milestone.**

Run tests, inspect outputs and report failures.

**11. Document decisions.**

Maintain architecture notes and a concise changelog. Decisions and handoffs go into `project-log.md`.

**12. Be pragmatic.**

This is a personal tool, not an enterprise SaaS application.

Avoid unnecessary authentication, multi-tenant architecture, payment systems, enterprise infrastructure and overengineering.

---

# 22. FIRST DEVELOPMENT TASK

Start with the existing repository, already imported here from:

https://github.com/kotyzap/Photo-Curator

Your immediate assignment:

1. Inspect the entire repository.
2. Read its README, security documentation and license.
3. Inspect the main application, duplicate detection, ranking and file organizer modules.
4. Identify architectural problems.
5. Identify risks to source photographs.
6. Check macOS Apple Silicon compatibility.
7. Review dependency health and security.
8. Create a target modular architecture.
9. Create a prioritized implementation plan.
10. Implement the first milestone: multi-source photo indexing, metadata normalization and non-destructive chronological organization.

Do not immediately implement all requested features.

Do not perform a complete frontend rewrite.

Do not introduce cloud dependencies without a clear reason.

Do not modify or delete original image files.

The initial milestone is successful when two folders of photos from different phones can be imported, indexed and displayed together in a correctly normalized chronological timeline, with confidence and provenance for uncertain timestamps.

After each milestone, provide:

- Summary of changes
- Files modified
- Tests run
- Test results
- Known limitations
- Recommended next milestone

**Final product goal:** A reliable, local-first AI Photo Curator that transforms unorganized photos from multiple people and devices into one intelligently curated, chronologically accurate, semantically searchable and safely exportable collection.

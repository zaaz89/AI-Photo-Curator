# M7 plan: finish the app around the trip workflow

**Date:** 2026-11-12  
**Agent:** Claude Code  
**Owner's goal:** "After a trip I put all my photos and my partner's photos on the Desktop, add them to the app, it sorts them (chronologically or however I want), checks duplicates and picks the better one by several criteria (closed eyes, blur, looking away), adds descriptions and everything else, and at the end prepares one folder that I just drop into Google Photos." A Google Photos connection comes later; not now.

Owner's decisions (2026-11-12): write corrected time, place and description **into the exported copies** (originals untouched); use **Apple Vision** on the Mac for face quality (no identity recognition, nothing leaves the Mac); ship as a **real Mac app** (own window).

## The workflow the app is built around

1. **New trip**: name, then one folder per person (for example "Me" and "Partner") from the Desktop. Analysis starts automatically.
2. **Check times**: two phones, one timeline. Shows device clocks, offers corrections with evidence.
3. **Best of each moment**: duplicate and burst groups; the keeper is chosen by face quality (eyes open, looking at the camera, face sharp), overall focus, resolution and composition, with the reasons shown. One key to accept, arrows to compare.
4. **Blurry photos**: review the blurry ones, keep or leave out.
5. **Events and places**: rename, merge, split.
6. **Descriptions** (optional, local AI, gentle on the GPU).
7. **Export for Google Photos**: one folder with the chosen photos, Live Photo videos next to their stills, corrected times, GPS and descriptions written into the copies, verified, with a manifest.

A checklist in the sidebar shows where the owner is; every step can be skipped and revisited.

## Design (Apple Native Experience, macOS HIG)

From the ui-ux-pro-max search (`style: apple-native-experience`): system typography (SF Pro via system-ui), semantic adaptive colours for light and dark, 8 pt spacing, restrained borders and shadows, consistent line icons in the SF Symbols style (inline SVG, no emoji), segmented controls, sheets for multi-step tasks, popovers for small choices, 150–250 ms purposeful transitions, `prefers-reduced-motion` and `prefers-reduced-transparency` fallbacks, visible focus, full keyboard use. Native window via AppKit + WKWebView, so the app has a Dock icon, a menu bar and no browser chrome.

## Build order

1. Swift helper: Apple Vision face quality and AVFoundation video thumbnails and metadata.
2. Face-aware keeper and keeper criteria in Settings.
3. Trip wizard and the guided checklist.
4. Culling: favourite and reject marks, multi-select and batch actions, sort options, move a photo to another event, undo.
5. Videos and Live Photos throughout (timeline, export).
6. "Export for Google Photos" preset with metadata written into copies via ExifTool and read back.
7. Mac app wrapper and installer script.
8. Review with the design and accessibility skills, fixes, tests, PR.

## Status (2026-11-12, Claude, branch `claude/m7-trip-workflow`)

Done: steps 1–4, 6, 7, 8 of the build order. Step 5 partly: videos show as tiles with a poster frame and duration, play in Quick Look and keep their Live Photo pairing in the export; no separate video timeline features.

What the owner sees: a trip picker and **New trip** sheet (name, one folder per person); a sidebar checklist of seven steps with Done/Next at the top of each step; All photos with filters (favourites, left out, videos, focus, person), sort (time, person, place, quality), multi-select (⌘/⇧ click, ⌘A) and a selection bar (favourite, leave out, keep, move to event); undo (⌘Z, toast); inspector with face facts, focus override and wallpaper mark; Quick Look for photos and videos; Export for Google Photos with preview and "Show in Finder" when it finishes.

Review (design-critique and accessibility-review skills) and fixes: Done/Next moved to the top (they were below long lists); export result now links to the folder; muted text darkened to pass 4.5:1 on the sidebar; link buttons at least 24 px high; focus kept inside sheets and returned on close; photo grids are listboxes with one Tab stop and arrow keys; `window.prompt` replaced by an in-page sheet (WKWebView has no prompt).

Security fix found on the way: the folder dialog spliced the prompt (a person's name) into AppleScript; it is now passed as an argument. Bug fixed: moving every photo out of an event crashed (empty event bounds).

Not verified: eye thresholds on real closed-eye photos; whether Google Photos shows the XMP/EXIF description after upload; VoiceOver end to end in the Mac window; the app on a fresh Mac (it needs the project folder, `uv sync`, ExifTool).

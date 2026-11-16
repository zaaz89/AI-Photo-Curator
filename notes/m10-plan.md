# M10 plan: quick review and a quality check you can trust

Owner's request (2026-11-16): useful, smart and intuitive features and commands. Go through everything fast with the arrows (→ keep, ← leave out), with a back step for a wrong decision. The quality check must be really good at closed eyes and blur, and a sharp subject on a blurred background (bokeh) is not a fault. No Google Photos connection. Status: proposal, waiting for the owner's OK.

## What the research says (2026-11-16)

Reddit could not be read (it refuses automated access, also in Chrome). Sources were DPReview, culling-tool reviews, GitHub issues and Apple's documentation; details are in the session notes.

- Fast tools are manual and instant: one key per decision, auto-advance, instant zoom (Photo Mechanic, Lightroom with auto-advance, Narrative Select).
- Swipe cleaners get complaints about lost progress, missing undo and deletes that need confirming. We never delete, save every decision at once and resume where the owner stopped.
- Closed-eye detection is the most reliable AI flag in reviews, but it fails on laughter and squinting, small background faces and sunglasses. Blur detection is the least reliable: whole-image measures flag bokeh, and a sharp background hides a shaken subject.
- A tool should never call a frame "best" when every frame of the moment is bad (an Aftershoot flaw in DPReview's review).
- Apple's Vision framework can do more on this Mac without downloads: face landmarks (eyes), face capture quality, salient-subject boxes, and an image aesthetics score that also recognises screenshots, receipts and documents. The aesthetics request's score range is not confirmed in Apple's docs yet; it is checked before use.

## 1. Quick review (the main new feature)

A full-window review of the album, one photo at a time, in time order. The AI's suggestion is already applied, so for most photos the owner only confirms.

| Key | Action |
|---|---|
| → | Keep (in the album), next photo |
| ← | Leave out, next photo |
| ⌫ or ⌘Z | Back: the previous photo comes back and its decision is undone (as many steps as needed) |
| Space | Skip, decide later |
| F | Favourite (in the album, 5 stars in the export) |
| Hold Z | 100 % zoom on the subject (faces first) |
| E | Faces of the photo large, eyes open or closed |
| ? | All keys on one card |
| Esc | Stop; the next quick review continues where this one ended |

- Each photo shows the AI's reason in words ("Eyes closed: Ana", "Subject blurred by movement", "Another frame of the same moment, the better one is kept") and, for a moment, its other frames in a strip below. → on another frame of a moment keeps it as well.
- A short colour flash and slide confirm every decision (green right, grey left). Back is always visible as a button too.
- Choose what to review: everything; only what the AI was unsure about (default when there is a lot); only left out.
- End card: kept / left out / skipped, with "Review skipped" and "Go to Story".
- Every decision is written at once (the existing ordered write queue with undo). No file is ever moved or deleted.

## 2. Quality check v2 (eyes and blur done properly)

Work in the Swift helper (Apple Vision) and the engine. Nothing is uploaded and no model is downloaded.

**Sharpness on the subject, not the whole image.** The subject is the main faces (largest one to three, background people ignored), else Vision's salient-subject boxes, else the sharpest tile. A photo is blurry only when the subject is soft; a soft background (bokeh) never counts. A movement check compares edge strength across directions on the subject, because the sharpest tile can still be shaken.

**Eyes per main face: open, closed or "can't tell".** "Can't tell" covers small faces, profiles, sunglasses and low landmark confidence. It never leaves a photo out. Laughter and squinting are compared with the same face position in the other frames of the moment, so a smile does not count as closed when nothing better exists. Only main faces count.

**Best frame of a moment.** Eyes first, then subject sharpness, then face capture quality and Apple's aesthetics score. When every frame is bad, the moment is marked "all frames have a problem" instead of naming a best one.

**Screenshots, receipts and documents** are suggested as left out (Apple's utility flag).

**Calibration on the owner's photos.** Built-in thresholds are guesses until measured. With the owner's OK, the 236-photo folder is analysed once (a few minutes now), and the owner marks about 60 photos in quick review (eyes closed, blurred, fine). Thresholds are then tuned to that, and the agreement rate is reported. Target: at least 9 of 10 flags right, and no bokeh portrait flagged.

## 3. Small smart things

- Resume where you left off (quick review and the Selection step).
- Commands: a menu with every action and its key; ⌘1–3 open the steps, ⌘R starts quick review, and ? shows the keys.
- Undo history: Edit ▸ Undo names the action ("Undo: leave out 3 photos").
- "Show only undecided" in the grids.

## Order and size

1. **M10a, quick review with back** (app only, uses the existing marks and undo). One PR.
2. **M10b, quality check v2 with calibration** (helper and engine). One PR; needs the owner's labelled sample.
3. **M10c, small smart things.** One PR.

Later, not in M10: import from the Photos app, Live Photo and RAW+JPEG as one tile, Slovenian search through Apple's on-device translation, chapter names from Apple's on-device language model.

## Questions for the owner

1. May the 236-photo folder be analysed for calibration, and will the owner label about 60 photos in quick review?
2. Should quick review show everything by default, or only what the AI was unsure about?

# M14c: Survey, deciding a moment

Owner feedback (2026-11-26, translated): "the process when I choose a photo, keep it or not, is not good enough; I need
both or more photos next to each other, smarter, better and easier to choose; tell me the shortcuts; think how to
improve further."

Benchmarks: Narrative Select (faces panel per frame, eye state), Photo Mechanic Survey, Lightroom Survey view (N frames
side by side, one keeper), Aftershoot (pre-picked best with reasons).

## 1. Critique of what was there (design-critique)

| Finding | Severity | Fix in M14c |
|---|---|---|
| Moments in the question review went through the single review one frame at a time (→ keep / ← leave out): the owner judged each frame without seeing the others | Critical | Survey: every frame of the moment side by side, decide the moment once |
| The compare view showed only two frames ("winner stays"), needed C to open and ←/→ to cycle challengers | Critical | All frames at once (2–6 in a row, more in a filmstrip); 1–9 picks directly |
| Only one keeper; "keep too" needed a separate button in Moments | Moderate | ⇧+click / ⇧1–9 add more keepers in the same view |
| Keys only behind `?`; owner asked "tell me the shortcuts" | Moderate | Always-visible shortcut bar + a one-time coach with the four keys that matter |
| The app's suggestion was visible as a badge, but not *why* or how sure | Moderate | "Best" badge, 1–3 reason chips per frame, a "Why" line, confidence pill, "Close call" |
| Faces sat in a side panel of the single review, not under the frames | Moderate | Face strip under every frame, same person in the same column |
| K / X meant keep / leave out in the grid but nothing in the review | Minor | K / X everywhere in the review family |

## 2. Layout

```
[Done] (ring) Moment 3 of 12  [Close call]                         [Zoom] [⌨]
              Frame 2 is the best: sharpest frame, eyes open on all faces
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│1  ✦ Best ✓│ │2        ○│ │3        ✓│ │4        ○│   equal height, as large as the space allows
│  photo    │ │  photo   │ │  photo   │ │  photo   │   focused frame: accent ring; keepers: green ring + ✓
└──────────┘ └──────────┘ └──────────┘ └──────────┘   others dimmed and sitting a little lower
[Sharp face][Eyes open]  [Eyes closed]  ...             reason chips (≤ 3, problems first)
 (Ana)(Bor)              (Ana)(Bor)                     face strip: one column per person, eye state ring
2 kept · 2 to Left Out                          [Back] [Skip] [Accept Suggestion] [Confirm ↩]
1–9 Pick  ⇧1–9 Also keep  ↩ Confirm  A Accept  ← → Frame  Z Zoom  ⌫ Back  ? All keys
```

- `surveyLayout` (CuratorCore): ≤ 6 frames in one row at equal height `min(room, (width − gaps) / Σ ratios)`; more than
  six, or frames that would be shorter than 120 pt: a sideways filmstrip, the focused frame up to 55 % of the width,
  the others 60 % of its height; the strip scrolls to keep the focused frame centred.
- Reason chips (`surveyChips`): Eyes closed, Motion blur, Blurry, Looking away, then Sharp face, Eyes open (or Sharp
  without faces). Built from data the app already has (focus tier, M10 quality reasons and blur, face boxes with
  state and looking-away). **Smiling and Horizon are not offered**: the engine measures `horizon_level` inside the
  aesthetic score and nothing about smiles reaches the app (no field in `/timeline`). Adding them = engine field +
  `SurveyChip` case + string.
- Why line: the engine's keeper reasons (`why_` strings); when there are none (moment built from photos), the best
  frame's positive chips.
- Confidence (`SurveyConfidence` from the engine margin): high ≥ 0.12 (the engine's `CLEAR_MARGIN`), medium ≥ 0.05,
  low < 0.05 = **Close call** (orange pill): the moment opens with synced 100 % zoom on the main face.
- Face strip (`SurveyFaces`): `matchFaces` by position on a reference frame (the recommended frame unless it shows no
  main face; then the frame with the most). Tab cycles the person; the active person is ringed in every frame and the
  zoom centres on that person's face in the focused frame (else where they are in the reference frame).

## 3. Decision model

| Action | Result |
|---|---|
| Open a moment | the recommended frame is the only keeper and focused |
| Click / 1–9 | that frame is the only keeper (and focused) |
| ⇧+click / ⇧1–9 | that frame is added as a keeper, or taken out again |
| K / X | focused frame kept too / left out (others unchanged; X may leave no keeper) |
| Return | confirm: keepers stay in the album, the rest go to Left Out; next moment |
| A | the recommendation as it is (whatever is selected), next moment |
| S | skip: next moment, nothing written |
| ⌫ / ⌘Z | back to the previous moment with the keepers that were chosen; its writes are undone |

Writes (`LibraryModel.applySurvey`): the engine keeps **one keeper per moment** (`POST …/duplicates/<id>/keeper`,
table `keeper_choices`), so multi-keep is stored as:
- `primary` = the recommended frame if it is kept, else the first keeper → `keep(group:photo:)` (also un-rejects it);
- every other keeper → marks `keep = true, rejected = false` ("keep too": `goesToAlbumDespiteFocus` exports it);
- every frame not kept → marks `rejected = true, keep = false` (shown in Left Out, reversible there);
- nothing kept → the engine keeper is left as it was and every frame is rejected (the export takes none).
Only marks that change are written. Each mark write is also on the window's undo stack. Back
(`LibraryModel.undoSurvey`) restores every frame's marks from before (`SurveyEntry.previous`) and the keeper to the
owner's earlier choice, or `null` (= the recommendation) when the app had chosen. A moment built from photos (C in
the single review) has no "chosen by you" flag, so its undo goes back to the recommendation.

Order (`SurveyMoment.byImpact`): close calls first, then more frames, then lower margin, then time. The hard, big
decisions come while attention is fresh; the easy tail can be accepted with A.

## 4. Flow

- **Questions station** → "Answer N questions" (`LibraryModel.answerQuestions`): moments without a clear best frame
  open in Survey (impact order); then the "Have a look" photos that are not frames of those moments go through the
  single review (→ keep, ← leave out, now with K / X and the bar). Clock questions unchanged (People & Clocks).
- After the last moment: completion card (seal bounces once, "Every moment is decided", tally, "Next: 4 photos to have
  a look at" or "On to your album"); Return continues at once, ⌫ goes back, otherwise it continues by itself after
  1.4 s. With no singles the review closes as finished and the path moves to Album.
- **Moments page** → "Survey" opens Survey from the selected moment on (page order); closing returns to the page.
- **Single review** → C opens Survey for the photo's moment; closing returns to the photo.
- Esc closes Survey (decisions so far are saved; the question review counts as not finished).
- First time only: coach card over Survey with 1–9, ↩, Z, ← → (`SurveyCoach.seenKey`); any key or Got It closes it,
  and that key still acts.

## 5. Keymap (the whole app, one table)

`ReviewKeymap` (CuratorCore/ReviewKeymap.swift) for the review family; the grid family is in `PhotoGrid` and
`notes/m12b-design-system.md`. Any key with ⌘, ⌥ or ⌃ is never the review's (menus, VoiceOver, ⌘Z pass through).

| Key | Survey (`.survey`) | Single review (`.single`) | Grid |
|---|---|---|---|
| 1 – 9 | that frame is the only keeper | – | 1 / 2 / 3 / 0: focus mark sharp / soft / blurry / auto |
| ⇧1 – 9, ⇧+click | add / remove an extra keeper | – | – |
| ↩ Return | confirm, next moment | – | – |
| A | accept the suggestion, next moment | – | – |
| ← / → | focus previous / next frame | leave out / keep, next photo | move selection |
| K | keep the focused frame too | keep, next photo | keep |
| X | leave out the focused frame | leave out, next photo | leave out |
| Z | 100 % on the face in every frame, synced; again: fit | 100 % on the main face | – |
| Space (hold) | 100 % while held, fit on release | skip | Quick Look |
| Tab | next face (zooms if not zoomed) | – | – |
| ⌫, ⌘Z | back to the previous moment (undo) | back, decision undone | – |
| F | favourite the focused frame (it becomes a keeper) | favourite | favourite |
| S | skip the moment | – | – |
| E | – | faces large | – |
| C | – | open Survey for this moment | – |
| ? | all keys | all keys | – |
| Esc | keys card, else close Survey | keys card, else close the review | clear selection |
| drag (zoomed) | pans all frames together | pans | – |

The keys card (`entries`), the bottom bar (`bar`) and the coach (`coach`) are built from the same table. ⇧+digit is
read from the physical key (`digit(forKeyCode:)`, number row and keypad), so it works on Slovenian and US layouts; on
US layouts the typed "!@#…(" also map. Space hold: key-up phase ends it; focus loss, scene-phase change, a new moment
and Z also end it, so a lost key-up never leaves the zoom on.

## 6. Motion (Motion tokens; Reduce Motion paths)

| What | Motion | Reduce Motion |
|---|---|---|
| Confirm (hero) | the confirmed frames are drawn once more on a non-interactive layer: keepers lift (−32 pt, 1.03, fade), others drop (+80 pt, 0.94, fade), `drop`; cleared after `motionBudget` | no layer |
| Next moment | slides in from the right (+80 pt + fade), `arrive`; Back from the left, `settle` | cross-fade |
| Pick / add / K / X | ring, ✓ (`symbolBounce`, `.replace`), dim and 6 pt sink of non-keepers, `quick` | no sink, no bounce |
| Focus | ring and (filmstrip) size, `quick` / `settle`; strip scrolls `settle` | instant |
| Counters | "Moment 3 of 12", tally: `numericText`; ring trims with `settle` | – |
| Completion | seal bounces once; card scales in 0.94 → 1 (`motionTransition`) | fade |

Never blocking: the session moves to the next moment in the same frame as the key; animations only follow state.

## 7. Copy (ux-copy)

Plain verbs, the app's words: "Confirm", "Accept Suggestion", "Skip", "Best", "Close call", "Frame 2 is the best: …",
"2 kept · 3 to Left Out", "Nothing kept: all frames go to Left Out" (orange, so an empty choice is never silent),
"Every moment is decided", "Next: 4 photos to have a look at". Slovenian uses the same structure
("Posnetek 2 je najboljši: …", "Ostane: 2 · Med izpuščene: 3"). Keys in the bar are one word each.

## 8. Code

- CuratorCore: `Survey.swift` (SurveyMoment, SurveyConfidence, SurveyDecision, SurveyEntry, SurveySession,
  SurveyChip + `surveyChips`, SurveyFaces + `faceReference`, `surveyLayout`, SurveyCoach, SurveyRequest);
  `ReviewKeymap.swift` (`.survey` context, `KeyAction`, `action(for:)`, `digit(forKeyCode:)`, `bar`, `coach`).
- App: `SurveyView.swift` (SurveyView, SurveyFrame, SurveyDepartingRow, SurveyProgressRing, ShortcutBar);
  `QuickReview.swift` hosts Survey (`ActiveSurvey`) and shows the bar; `LibraryModel` `startSurvey`, `surveyRequest`,
  `applySurvey`, `undoSurvey`, `questions()`; Moments page button.
- Removed: `CompareView`, `CompareSession`, compare keymap context and its commands, 12 strings only they used.
- Tests: `SurveyTests.swift` (14), `ReviewKeymapTests.swift` (survey keys, bar and coach).

## 9. Open

- Not compiled (Linux); see the log entry for compile-risk spots.
- Smiling / Horizon chips need engine fields.
- Up to 6 originals decode at 100 % at once when zoomed (only the frames on screen); watch memory on 60 MP RAWs.
- `need_you` count after "nothing kept": the moment's engine keeper stays, so the engine may still count it until the
  question review finishes (which marks the step).

# M12b UX and accessibility audit (static)

Branch: open M12 "Sorting" PR (`SortingStage.swift` new). Scope: `mac/Sources/PhotoCurator/*.swift`, `mac/Sources/CuratorCore/Strings.swift`, `CuratorCore/Sorting.swift`.

## Method and limits

- Static audit from code on Linux. The app was not run, no screenshots, no VoiceOver, no Accessibility Inspector. Frameworks used: design critique (hierarchy, flow, consistency), WCAG 2.1 AA review (perceivable, operable, robust), UX copy review (clarity, consistency, confirmations, empty states).
- Evidence column: **S** = seen in code (the behaviour follows from the source). **V** = needs a visual or runtime check before acting (contrast ratios, perf, overlap, real wording fit).
- Counts in section 5 come from regex scans of `PhotoCurator/*.swift`. They are indicative (computed values such as `size * 0.4` are listed separately; `radius` includes shadow radii).
- Slovenian remarks are from a reading of the strings, not a native review. Items marked "native check" need Žaž or a translator to confirm.
- Contrast numbers are estimates from system color values (orange #FF9500 and red #FF3B30 with white text give about 2.2:1 and 3.6:1). Measure on real photos and glass.
- Nothing in the repo was modified.

## What already works (keep)

- Quick Review has one decision per key press (no auto-repeat), Back that also undoes, a keys card, a persisted bookmark (`QuickReview.swift:61-66`).
- Marks go through `UndoManager` with trip guard (`LibraryModel.swift:307-345`).
- Reasons exist for keeper choice (`StepSelection.swift:~107`), for tray photos (`SortingStage.swift:866`) and in the "Decided automatically" card text (`Strings.swift:93`).
- Safety copy is consistent: "Your originals are not changed", "Nothing is deleted" (`Strings.swift:~381`).
- Reduce Motion is honoured in `AIRing`, `Shimmer`, `StageBackground`, tile springs (`SortingStage.swift:366`, `ActivityViews.swift:17`, `PhotoGrid.swift:156`).
- Hero text has a scrim (`AlbumHome.swift:51-55`). Glass is limited to floating controls plus the tray cards (see F27).

## Prioritized findings

P0 = wrong or misleading now, or blocks a user group. P1 = clear friction or risk, fix in M12b/M13. P2 = polish and debt.
Effort: S under half a day, M about 1 to 2 days, L more.

| # | Pri | Area | Finding | File:line | Fix | Eff | Ev |
|---|-----|------|---------|-----------|-----|-----|----|
| 1 | P0 | Trust, copy | The Stage calls photos "Removed" (tray, counter, funnel help, SL "odstranjeno") although nothing is ever deleted and the owner can put them back. Contradicts the hard safety rule and `lead_selection`. The tray also mixes auto blur and the owner's own "left out" under one label. | `Strings.swift:295,297,303,306,395`; `SortingStage.swift:719,788` | Rename to "Left out" (SL "Izpuščeno") everywhere. Keep the reason line per photo; group by reason inside the tray (Blurry, Screenshot, Left out by you). | S | S |
| 2 | P0 | States | Stage header title has no stopped or failed case. After Stop or a failed analysis it shows "The album is sorted" (photos exist) or "Waiting for the photos". The `default` branch says "Arranging by day and time" for any unknown phase. Failure is invisible on this page. | `SortingStage.swift:684-699` | Add `stopped` and `failed` titles with the reason and a primary "Analyse again". Replace the `default` with a neutral "Working". | S | S |
| 3 | P0 | Flow | Dead end during the post-analysis acts (quality reveal, moments): the action row renders only `Spacer()`. Next appears only after `settled`. No way to skip the animation or leave with a clear action. | `SortingStage.swift:731,738-740` | Show "Skip animation" (Space or Esc) from the first frame. Always show Next, disabled with a reason until settled. | M | S |
| 4 | P0 | Huge counts | `stageFlow` stops shrinking at `minHeight` 28 and returns an overflowing layout. The page is `.clipped()` and has no scroll, so photos beyond the viewport are invisible and untappable. Every photo is a live view with a spring animation. 8 thumbnail loaders run at once. Tuned for 236 photos. | `Sorting.swift:83-84`; `SortingStage.swift:359-377,362,184` | Cap drawn tiles (about 300, sample per day, "+N" chip). In settled state use a scrolling `LazyVGrid` per day. Skip the choreography above a threshold. | L | S (overflow), V (perf) |
| 5 | P0 | A11y | VoiceOver gets only the file name for Stage tiles. Verdict, reason and stacked count are visual only. In the grid, the tile label omits blurry tier, eyes closed, extra frame and auto-removed. Status is conveyed by badge color only. | `SortingStage.swift:642-643`; `PhotoGrid.swift:188-190,215-221,194-206` | Add verdict and reason to `accessibilityLabel`/`Value` using the same `why2_*` strings. Use `.accessibilityRepresentation` or `accessibilityElement(children: .combine)` on the tray. | S | S |
| 6 | P0 | A11y | Contrast: white text on system orange and red capsules (about 2.2:1 and 3.6:1 at 10 to 11 pt). Orange and green text on an 18% tint of itself in light mode is about 2 to 2.5:1. | `PhotoGrid.swift:195-205`; `StepSelection.swift:~370-374`; `QuickReview.swift:184` | Semantic tokens with AA-checked fg/bg pairs (see section 5). Dark label on orange, or solid darker fill. | S | V |
| 7 | P0 | Trust, undo | Reversible actions give no visible confirmation or undo affordance: tray "Put back", "Put all back", "It's fine", "Leave out" (change only via hidden Cmd+Z, which in a popover may not reach the main window's manager). "Accept the Rest" marks every following moment reviewed and the step done with no undo and no confirm. "Split this day automatically again" wipes chapter names with no confirm or undo. | `SortingStage.swift:840-861`; `StepSelection.swift:213-218`; `StepStory.swift:24`; `LibraryModel.swift:418` | Toast with Undo button ("Put back 3 photos. Undo") using `library.message` plus an action. Register undo for accept-rest. Confirm dialog naming the count for reset chapters. | M | S |
| 8 | P1 | Errors | Errors fade after 4 s, are not announced to VoiceOver (trait `.updatesFrequently` is not an announcement), and show raw text ("HTTP 500", engine strings, `job.error`). The engine start failure string is English only and includes a path. `stopJob` swallows errors with `try?`. | `MainWindow.swift:~288-296`; `LibraryModel.swift:766-771,713`; `StepExport.swift:154`; `EngineController.swift:48` | Sticky error banner with Dismiss and "Details". Post `AccessibilityNotification.Announcement`. Map HTTP codes to `Strings`. Surface `stopJob` failures. | M | S |
| 9 | P1 | A11y, Quick Review | The main photo has no label, decisions are not announced, and the view swallows arrow keys. A VoiceOver user cannot tell which photo is shown or what happened. The flash icon and zoom are visual only. | `QuickReview.swift:~150-160,60-72` | Label = filename, clock, owner, reasons. Announce "Kept, 12 of 80" after each decision. Add `accessibilityAction`s for keep, leave out, skip, back. | M | S |
| 10 | P1 | A11y, motion | Reduce Motion gaps: `ScanBand` always sweeps; header `.push` transition and `.animation(.snappy)` unguarded; Quick Review slide and scale flash; unguarded `withAnimation`/`.transition` in AlbumHome (5), StepSelection (5), MainWindow (8), StepExport (2). Reduce Transparency, Increase Contrast, Differentiate Without Color are never read (zero hits). | `SortingStage.swift:578,712-714,764,812`; `QuickReview.swift:159,236,245` | One `Motion` helper that returns `nil` or a fade under Reduce Motion. Read the three other environment flags where glass or color-only cues are used. | M | S |
| 11 | P1 | Pro interaction | No real compare. Moment frames show cropped faces side by side (`FaceComparison`) but no synced full-frame pan and zoom, no 2-up, no pick-by-number. Details in section 7. | `QuickReview.swift:31-40`; `StepSelection.swift:~110-125` | Compare mode with synced zoom on a chosen face (section 7, item A). | L | S |
| 12 | P1 | Pro interaction | "Hold Z to zoom" is 3x on a thumbnail of at most 2048 px, so focus cannot be judged at 100%. Blur verdicts are exactly what the owner must verify. | `QuickReview.swift:~137-153`; `Thumbnails.swift:11-12` | On Z load the original through `CGImageSource` (read only) for the visible region, anchored on the subject/face, 100% not 300%. | M | S |
| 13 | P1 | Flow | Tray decisions are made on 104 pt thumbnails, no larger preview, no Quick Look, no keyboard inside the popover. | `SortingStage.swift:851,816-847` | Space opens Quick Look on the focused cell; arrow keys move; larger cell (150 to 220) in a sheet when count is above 12. | M | S |
| 14 | P1 | Keyboard | Stage tiles use `onTapGesture` (not focusable). Tapping an album tile does nothing (dead end); only tray or "check" tiles open the tray. Only the three tray cards are reachable by Tab. | `SortingStage.swift:367-368,501-505` | Tap on an album tile selects it and opens Quick Look or the Inspector. In settled state make tiles `Button`s in a focus section. | M | S |
| 15 | P1 | Keyboard, IA | The Stage has no menu shortcut. Menu order does not match the sidebar or the flow: Home 0, steps 1 to 3, "People & Clocks" 4, then 5, 6. Clocks come before sorting in the flow but sit after Export in the menu. Copy says "3 steps" while Stage and People & Clocks are extra pages. | `App.swift:74-82`; `Guide.swift:8-10`; `Strings.swift:169,368,396,496` | Proposed: Home 0, People & Clocks 1, Sorting 2, Selection 3, Story 4, Export 5, All Photos 6, Left Out 7. Decouple key from `GuideStep.number`. Fix "of 7 steps" and "of 3". | S | S |
| 16 | P1 | Hierarchy | Competing primaries: Home shows a prominent NextCard button plus a second prominent teal button; Selection has a prominent Quick Review next to "Accept the Rest" and per-frame glass buttons; Export prominent green plus Show in Finder. Home stacks 8 sections. | `AlbumHome.swift:135,199`; `StepSelection.swift:20,111`; `AlbumHome.swift:14-24` | One prominent action per screen (the next step). Demote the rest to `.glass`. On Home, fold `StageLink` into the funnel header. | S | S |
| 17 | P1 | Flow | Funnel row "screenshots" goes to the Stage page but does not open the Removed tray its help text promises. The "Have a look" tray starts the generic `.decisions` review, not the tray's photos (a subset mode exists). | `AlbumHome.swift:289`; `SortingStage.swift:838`; `QuickReview.swift:23` | Add `library.openTray` and set it on navigation. Start review with the tray ids (`subset`). | S | S, V |
| 18 | P1 | Keyboard, consistency | Same verb, different key by screen: leave out = X (grid), Left (Quick Review), button (Selection). Space = Quick Look (grid) vs Skip (Quick Review). Esc clears selection (grid) vs closes (review). Plain digits 0 to 3 silently overwrite the focus mark with no hint, toast or menu entry. | `PhotoGrid.swift:74,77-94,89`; `QuickReview.swift:62-66`; `App.swift:58-61` | List digits and X in the Photo menu. Toast after digit marks. Document the two key families (grid vs review) in the keys card. | S | S |
| 19 | P1 | Keyboard | Hold-Z uses key up and down. If focus leaves (popover, system dialog) the up event is lost and zoom sticks. | `QuickReview.swift:70-73` | Reset `zoom` on `onChange(of: scenePhase/focused)`. Or make Z toggle. | S | V |
| 20 | P1 | States, export | Export has no cancel button while running (Stop only in the Photo menu). Preview failure leaves a spinner forever. Raw `job.error` is shown. Preview shows 30 thumbnails with "+N". | `StepExport.swift:~126,149-154,172-174`; `App.swift:68` | Cancel button next to progress, error state with Retry, humanised error. | S | S |
| 21 | P1 | Trust | Auto-removed screenshots and documents have no badge in the grid; reason exists only in the tray and Quick Review. Dimming (opacity 0.4) applies only to owner-rejected photos. | `PhotoGrid.swift:160-163,194-215` | Badge "Screenshot" or "Document" (icon plus text), and a filter chip. | S | V |
| 22 | P1 | Copy, destructive | "Finish Album" removes working data (marks, analysis) but the button and title do not say so. The unexported warning is in the body, not the title. | `Strings.swift:157-165`; `MainWindow.swift:226-243` | Title "Clear working data for “X”?", button "Clear Data", unexported warning first. See section 6. | S | S |
| 23 | P2 | A11y | `FaceCrop` accessibility labels are hard-coded English, against the project rule that every string lives in `Strings.swift`. | `GuideChrome.swift:319` | Add `eyes_closed`, `eyes_unsure`, `eyes_open` keys. | S | S |
| 24 | P2 | A11y | Counters are 5 separate text pairs ("12", "read"). Source chips and tile cluster are not grouped. | `SortingStage.swift:716-720,755-768` | `accessibilityElement(children: .combine)` with "12 in the album". | S | S |
| 25 | P2 | A11y | Color-only state in small tiles: verdict glyph hidden under 34 pt, so "to look at" is an orange border only, "left out" a desaturation only. | `SortingStage.swift:604-612,598-600` | Minimum glyph (6 pt dot or ring shape) and read `accessibilityDifferentiateWithoutColor`. | S | V |
| 26 | P2 | A11y | No `ScaledMetric` anywhere (0 hits), 20 fixed `.system(size:)` sites. Hero 42 pt and stage 26 pt titles do not follow text size. | see section 5 | Map to text styles or `ScaledMetric` for display sizes. | M | S |
| 27 | P2 | Contrast, glass | Tray cards: `.regular.tint(0.12).interactive()` glass over an animated blurred gradient, text `white.opacity(0.6)`. Overlap of glows gives roughly 4 to 5:1. Source chips use `.ultraThinMaterial` on the same background. | `SortingStage.swift:795,799,809,672` | Raise secondary text to 0.72 or more. Test with Reduce Transparency and over saturated photos. | S | V |
| 28 | P2 | Copy | `trOr` falls back to the raw engine code ("movement_blur") when a reason key is missing. | `SortingStage.swift:868`; `LibraryModel.swift:112` | Fallback to a generic "Other reason" and log the code. | S | S |
| 29 | P2 | Copy | Stale strings: `stepsProgress` says "of 7 steps"; `phase_describing` "Writing descriptions" is a dropped feature; `exportHelp` mentions "classic view for now". | `Strings.swift:169,264,199` | Remove or update. | S | S |
| 30 | P2 | States | `StageLink` only appears on Home between cards, so the only way back to the review of auto-removed photos is easy to miss after the first run. | `AlbumHome.swift:18,873-887` | Add the Stage to the funnel header and to the Selection page as "Review what the app left out". | S | S |
| 31 | P2 | Hierarchy | Stage forces dark color scheme and animated glows regardless of system appearance. Rest of app follows system. Likely intentional, check against light mode. | `SortingStage.swift:747`; `QuickReview.swift:54` | Keep, but then use the same dark tokens for Quick Review and document it. | S | V |
| 32 | P2 | Keyboard | Next on the Stage and "Align" on People & Clocks have no default action key. Chip-style segmented controls rely on mouse for acceptRest. | `SortingStage.swift:731`; `StepPhotos.swift:254` | `.keyboardShortcut(.defaultAction)` on the single prominent button per screen. | S | S |
| 33 | P2 | Loading | Thumbnail has a missing state but no error detail; thumbnails fail silently (`try?`) and `missing` shows a generic icon with no label. Quick Review photo has no placeholder if the 2048 thumbnail is slow. | `Thumbnails.swift:20-47`; `QuickReview.swift:~137` | Show spinner then low-res fallback (260 already cached), label "Cannot read file". | S | V |

## Flow notes per screen (primary action)

| Screen | Primary action | Competing or missing |
|--------|----------------|----------------------|
| Album Home | Next step (NextCard) | Second prominent teal button, Quick Review, 8 stacked sections (F16). Stage link is a quiet text row (F30). |
| Sorting (Stage) | Running: none (Stop only). Settled: Next to Selection | No action during acts (F3). Replay and Next fine. Tiles dead end (F14). No failed or stopped state (F2). |
| People and Clocks | Align (prominent), then No | Manual shift hidden in a popover icon (label present). No default key (F32). |
| Selection | Quick Review (prominent) | Competes with Accept the Rest (F7, F16). Three segments with counts: good. |
| Story | Done (sheet) | Reset chapters without confirm (F7). |
| Export | Choose Folder and Export | No cancel, no failure state (F20). |
| Quick Review | Yes, keep (prominent green) | Good: Back, Skip, No are secondary. A11y gaps (F9). |
| Grid | Select then F, X, 0 to 3 | Silent digit marks (F18). Empty states exist (`PhotoGrid.swift:109-123`). |

## 5. Consistency debt inventory

### 5a. Counts per file (PhotoCurator/*.swift)

Columns: fixed font sizes, corner or shadow radii, `.padding(...)` calls, `spacing:` args, `Color(red:)` literals, animation calls, `opacity(...)` literals, semantic text styles, system color names.

| File | Fixed font | Radius | Padding | Spacing | RGB | Anim | Opacity | Text styles | Sys colors |
|------|-----------:|-------:|--------:|--------:|----:|-----:|--------:|------------:|-----------:|
| ActivityViews | 0 (+1 computed) | 3 | 3 | 7 | 5 | 4 | 3 | 6 | 1 |
| AlbumHome | 7 | 10 | 21 | 25 | 0 | 5 | 8 | 14 | 19 |
| GuideChrome | 2 (+4 computed) | 8 | 24 | 17 | 0 | 5 | 8 | 11 | 22 |
| Inspector | 0 | 1 | 10 | 9 | 0 | 0 | 0 | 9 | 3 |
| MainWindow | 0 | 1 | 11 | 4 | 0 | 3 | 1 | 7 | 3 |
| NewAlbumWizard | 1 | 3 | 3 | 9 | 0 | 1 | 1 | 11 | 1 |
| PhotoGrid | 0 | 3 | 14 | 3 | 0 | 3 | 5 | 6 | 11 |
| QuickReview | 3 | 5 | 18 | 14 | 0 | 3 | 6 | 9 | 15 |
| SettingsView | 0 | 0 | 0 | 2 | 0 | 4 | 0 | 9 | 0 |
| SortingStage | 6 | 7 | 11 | 14 | 6 | 16 | 12 | 10 | 20 |
| StepExport | 0 | 2 | 6 | 14 | 0 | 2 | 1 | 11 | 5 |
| StepPhotos | 1 | 3 | 12 | 17 | 0 | 0 | 1 | 13 | 1 |
| StepSelection | 0 | 8 | 17 | 18 | 0 | 3 | 1 | 10 | 7 |
| StepStory | 0 | 5 | 7 | 11 | 0 | 0 | 0 | 10 | 0 |
| Other (App, Thumbnails, ...) | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 2 | 0 |
| **Total** | **20** | **59** | **157** | **165** | **11** | **50** | **47** | **138** | **108** |

### 5b. Distinct values used

| Category | Distinct values (count of uses) |
|----------|----------------------------------|
| Fixed font sizes (14 literals) | 10, 11, 13/15 (stage day label), 20, 22, 26 (x4), 30 (x2), 34 (x2), 40, 42 (x2), 44, 64, 90, 96. Computed: `size*0.4`, `0.42`, `0.18`, `0.16`, `max(10,min(18,h*0.16))` |
| Text styles | callout 47, caption 33, title3 21, headline 16, title2 11, caption2 7, title 2, subheadline 1 |
| Corner radii (15) | 8 (10), 16 (8), 22 (8), 18 (4), 20 (4), 12 (4), 10 (4), 14 (4), 26 (3), 24 (2), 28, plus 2, 3, 0 (small bars). Stage tile uses `min(12, h*0.12)` |
| Padding values (25+) | 16 (9), 20 (8), 24 (5), 18, 14, 7, 6, 4, 8; h 10 (8), h 8 (7), h 6 (7), v 6 (6), v 2/3/4, h 12/14/22/24/32, top 6, bottom 14/18 |
| Stack spacing (17) | 14 (24), 10 (23), 12 (20), 8 (19), 16 (16), 6 (13), 4 (11), 0 (10), 2 (10), 18 (6), 24 (3), 1, 3, 5, 28, 30, 34 |
| Opacity (23) | 0.6 (5), 0.55 (4), 0.08 (4), 0.18/0.2/0.12 (3 each), 0.85/0.7/0.3/0.8/0.65/0.35/0.5/0.25 (2 each), 0.05, 0.14, 0.22, 0.28, 0.45, 0.72, 0.75, 0.88, 0.9 |
| Animations (22 forms, 50 calls) | `.snappy` 20, `.snappy(0.25)` 4, `(0.2)` 3, `(0.15)` 2, `(0.22)`, `(0.18)`; `.spring(duration 0.35)` 2, `(0.4)`; stage springs response/damping: 0.55/0.78, 0.7/0.8, 0.7/0.8 reused, 0.75/0.76, 0.8/0.7, 0.8/0.74, 1.0/0.82; ease: out 0.15/0.18/0.2/0.4, inOut 0.15/0.35/0.55/0.8/9 |
| Hardcoded `Color(red:)` (9) | AI ring: (.25,.55,1.0) x2, (.62,.38,1.0), (1.0,.35,.62), (1.0,.62,.25). Stage: (.42,.36,1.0), (0,.72,.95), (.98,.36,.62), (1.0,.62,.2). Removed: (1,.42,.42). Stage bg: (.05,.05,.08). Two near-duplicate 4-color palettes (`ActivityViews.swift:6-8`, `SortingStage.swift:545-547`) |
| System colors | white 39, green 23, orange 23, black 10, pink 4, blue 3, purple 3, gray 2, red 1; person palette `GuideChrome.swift:19` |

### 5c. Semantic color conflicts (kept, removed, look, stacked)

| Meaning | Where and what is used today | Problem |
|---------|------------------------------|---------|
| Kept | `.green` (tile glyph `SortingStage.swift:652`, QR `QuickReview.swift:111,184,208`, chips `StepSelection.swift`) | Consistent. Needs a dark-surface and a light-surface variant. |
| Removed or left out | Stage coral (1,.42,.42) `SortingStage.swift:547`; QR leave-out grey `.secondary`/white 0.7 (`QuickReview.swift:111,153`); `.gray` in Home funnel (`AlbumHome.swift:279`); grid blurry badge `.red` (`PhotoGrid.swift:199`) | Four treatments for one idea. |
| Look (to check) | `.orange` Stage border and counter, eyes-closed ring, soft tier badge, warn chips | OK. But QR also uses `.orange` for "skipped" (`QuickReview.swift:111`), which means a different thing. |
| Stacked | `stageColors[1]` cyan (`SortingStage.swift:652,718`) | Only used on the Stage; grid uses black 55% circle for the same state (`PhotoGrid.swift:211`). |

### 5d. Proposed tokens (derived from values already used)

**Spacing** (snap rule: 2 to 4 hairline, 6 to 4 or 8, 10 to 8 or 12, 14 to 12 or 16, 18 to 16 or 20, 22 to 24)

| Token | pt | Absorbs |
|-------|---:|---------|
| `space.hair` | 2 | 1, 2, 3 |
| `space.xs` | 4 | 4, 5, 6 |
| `space.sm` | 8 | 7, 8, 10 |
| `space.md` | 12 | 12, 14 |
| `space.lg` | 16 | 16, 18 |
| `space.xl` | 24 | 20, 22, 24 |
| `space.xxl` | 32 | 28, 30, 32, 34 |

**Radii**

| Token | pt | Use |
|-------|---:|-----|
| `radius.sm` | 8 | thumbnails, grid tiles, popover cells (10 uses) |
| `radius.md` | 12 | stage tile max, small cards, chips with text (absorbs 10, 12, 14) |
| `radius.lg` | 16 | source chip, preview blocks, panels (absorbs 16, 18) |
| `radius.xl` | 24 | tray cards, secondary panels, moment panel (absorbs 20, 22, 24, 26) |
| `radius.hero` | 28 | album hero |
| `radius.pill` | capsule/circle | badges, counts, toasts |

**Type roles** (macOS text styles: largeTitle 26, title 22, title2 17, title3 15, headline 13 bold, body 13, callout 12, subheadline 11, footnote 10, caption 10; verify on target OS)

| Role | Maps from | Spec |
|------|-----------|------|
| `type.display` | 42, 40, 44 | `ScaledMetric` base 42 bold (hero) |
| `type.stageTitle` | 26 bold, 30 | `.largeTitle` bold |
| `type.stat` | 26 semibold rounded, 22 bold rounded, 20 | `.title` rounded, monospacedDigit |
| `type.title` | title2, title3, 15, 13 (day label) | `.title2`/`.title3` |
| `type.body` | callout 47, headline 16 | `.callout` and `.headline` |
| `type.caption` | caption 33, caption2 7, 11, 10 | `.caption` and `.caption2` |
| `type.glyph` | 64, 90, 96 | decorative, `accessibilityHidden` |
| `type.badge` | 11 bold rounded, 10 | `.caption2` bold rounded |

**Semantic colors** (each with light and dark value and an AA-checked foreground)

| Token | Value today | Rule |
|-------|-------------|------|
| `status.kept` | system green | solid fill with dark label, or tint with `.primary` text |
| `status.removed` | (1,.42,.42) | replaces red badge, grey leave-out and gray funnel; always with icon |
| `status.look` | system orange | not used for "skipped" |
| `status.skipped` | neutral (`.secondary` fill) | new, frees orange |
| `status.stacked` | (0,.72,.95) | also used for the grid stack badge |
| `ai.gradient` | one 4-stop set: (.42,.36,1), (0,.72,.95), (.98,.36,.62), (1,.62,.2) | replaces both palettes |
| `surface.stage` | (.05,.05,.08) | shared by Stage and Quick Review |
| `text.onDark.primary/secondary/tertiary` | 0.9 / 0.72 / 0.55 | replaces 0.6 to 0.88 spread; secondary at 0.72 or higher for AA |
| `fill.onDark.1..4` | 0.08 / 0.12 / 0.18 / 0.25 | absorbs 0.05 to 0.28 |

**Motion** (4 named springs plus one fade; each routed through a Reduce Motion helper)

| Token | Value | Replaces |
|-------|-------|----------|
| `motion.quick` | `.snappy(duration: 0.2)` | snappy 0.15, 0.18, 0.2, 0.22, 0.25 (selection, favourite, flash, zoom) |
| `motion.standard` | `.snappy` (default) | 20 bare uses (page, count, title, panel) |
| `motion.settle` | `.spring(duration: 0.4)` | spring 0.35, 0.4 |
| `motion.stage` | `.spring(response: 0.75, dampingFraction: 0.78)`; slow variant response 1.0 for the final settle | seven stage springs (0.55 to 1.0, damping 0.7 to 0.82) |
| `motion.fade` (not a spring) | `.easeOut(duration: 0.18)`; ambient loops stay out of the system | easeOut 0.15 to 0.4, easeInOut 0.15 to 0.8 |

## 6. UX copy

### 6a. Terminology (fix the term, then sweep both languages)

| Concept | Current EN | Current SL | Problem | Proposed EN | Proposed SL |
|---------|-----------|-----------|---------|-------------|-------------|
| Photo not in album | Removed (295,297), Left Out (205), left out, "stay out" | odstranjeno, Izpuščene, zunaj | "Removed" implies deletion; 3 terms for 1 state | Left out | Izpuščeno / Izpuščene |
| Grouped near-duplicates | Stacked (294), Stacking (281), grouped (381), extra frames (389) | zloženo, Zlagam, združeni | 3 verbs for one idea | Grouped (visual metaphor only on stage) | Združeno |
| Tray name | Have a look (299), to look at (296) | Poglej, za pogled | Vague, imperative vs noun | To check | Za preverjanje |
| Sorting | Sorting (275) vs Sort menu (192) | Sortiranje vs Razvrsti, Razvrščam, "Glej, kako sortiram" | EN reuses one word for two meanings; SL mixes loanword and native | Stage "Sorting"; menu "Order By" | Razvrščanje; menu "Razvrsti po" |
| Burst frame | shots, frames, photos, moment | posnetek (frame and shot and screenshot) | "posnetek" overloaded | frame (in a moment), photo | kader (native check), fotografija; "posnetek zaslona" stays |
| Source device | Camera clocks (86,418) | Ure naprav, Ure fotoaparatov, Naprava | Phones are not cameras; two SL forms | Device clocks | Ure naprav |
| Bring back | Put back (309), bring it back (447), Keep (206) | Vrni v album / vrneš / Obdrži | Same action, three verbs | Put Back in Album | Vrni v album |
| Redo / Replay | Redo (504), Replay (291) | Ponovi / Ponovi | Identical SL | Redo; Replay Sorting | Uveljavi znova; Predvajaj znova |
| Engine | engine, "The Engine Did Not Start" (248) | pogon | Dev jargon; "pogon" also means drive | Background service | Storitev v ozadju |
| Owner's choice | chosen by you, left out by you | izbral si ti, izpustil ti, "Izpustil si jo" (312) | Gendered verb, awkward order | By you | Po tvoji izbiri |
| Detail panel | Inspector (200) | Inšpektor | Calque (native check) | Details | Podrobnosti |
| Tray (container) | tray | pladenj | Metaphor does not carry | group or "Left out" section | skupina / razdelek |
| Skip list | Review skipped (513), Review left out | Preglej preskočene | EN reads as past tense | Review Skipped Photos; Review Left-Out Photos | unchanged |
| Steps | Album Steps (tripSteps), Guide, Three steps (396), Step %d of 3 (496), "7 steps" (169) | Koraki, Vodnik | Count and name drift; Stage and People are not counted | Steps (Sorting is "Sorting", People is "People & Clocks") | Koraki |
| trip vs album | key names `trip`, UI "Album" | Album | Internal only, but `tripSteps`, `noTripsTitle` leak into copy audits | Album everywhere | Album |

### 6b. EN strings to rewrite

| Key and line | Now | Issue | Proposed |
|--------------|-----|-------|----------|
| `acceptRest` 113, 434 | Accept the Rest | Unclear scope, bulk and irreversible | Keep the App's Choice for the Rest (button), keep help text, add Undo |
| `itsFine` 311 | It's fine | Ambiguous (fine for what?) | Keep in Album |
| `stop` 255 | Stop | Stops what? | Stop Analysis |
| `done` in tray 109 | Done | Popover dismiss | Close |
| `counter_check` 296 | to look at | Counters are nouns | to check |
| `trayEmpty_check` 302 | Nothing waits for you | Anthropomorphic, vague | Nothing to check |
| `trayEmpty_removed` 300 | Nothing blurry | Tray also holds left-out photos | Nothing left out |
| `stagePhase_other` 279 | Arranging by day and time | Used as a catch-all for unknown phases | Working |
| `why2_eyes_unsure` 528 | Eyes: can't tell | Terse | Can't tell if eyes are open |
| `no` / `reject` 424, 133 | No / Reject | Same action, two labels, "No" has no object | Don't Align |
| `finishAlbum` 157, `finishTitle`, `finishConfirm` | Finish Album / Finish "X"? / Finish Album | Hides that data is removed (F22) | Clear Working Data… / Clear working data for "X"? / Clear Data. Body leads with "Not exported yet: your marks will be lost." |
| `momentKeys` 440 | symbol-heavy one-liner | Not read well by VoiceOver | Keep visual line; add `accessibilityLabel` with words |
| `stageDoneSub` 284 | Everything can be put back with one click. | Good; but only valid while undo or put back is visible | Keep, and link to the tray |
| `stageSummary` 285 | Taken: %d → in the album: %d | Arrow as the only connector | %d taken, %d in the album |
| `reviewNothingText` 516 | Choose All above... | Refers to a control by position | Choose All in the filter to go through every photo. |
| `exportHelp` 199 | (classic view for now) | Stale | Remove |

### 6c. SL strings that read as machine-translated or inconsistent (native check)

| Key and line | Now | Issue | Proposed |
|--------------|-----|-------|----------|
| `stageWatch` 288 | Glej, kako sortiram | Colloquial, first person, loanword | Oglej si razvrščanje |
| `stageReplay` 289 | Pokaži sortiranje znova | Loanword; clashes with `replay` | Predvajaj razvrščanje znova |
| `stageLinkText` 290 | Kako so bile fotografije razvrščene in kaj je odstranjeno | "odstranjeno" implies deletion | ...in kaj je izpuščeno |
| `counter_stacked` 294 | zloženo | Physical metaphor | združeno |
| `reason_leftOut` 312 | Izpustil si jo | Masculine, assumes object gender | Izpuščeno po tvoji izbiri |
| `why_chosen by you` | izbral si ti | Odd word order | po tvoji izbiri |
| `warn_rejected by you` | izpustil ti | Fragment | izpuščeno po tvoji izbiri |
| `working`, `phase_describing` 252, 264 | Delam na tvojih fotografijah / Pišem opise | First person, dead feature | Obdelujem fotografije / remove |
| `momentsAuto` 93 | Samodejno odločeno: %@ (odprte oči, ostrina, pogled v kamero) | Reads as a literal list | Samodejno izbrano: %@ (odprte oči, ostrina, pogled v kamero) |
| `funnelHelp_screenshots` 395 | ...pladenj Odstranjeno... | Metaphor plus "odstranjeno" | ...razdelek Izpuščene... |
| `engineFailed`, `engineUnreachable` 248 | Pogon se ni zagnal / Pogon se ne odziva | "Pogon" ambiguous | Storitev se ni zagnala / se ne odziva |
| `redo` 504 | Ponovi | Same as `replay` | Uveljavi znova |
| `quickReviewHelp` 507 | → da, ← ne | Fine, but "Samo kjer je potrebna odločitev" is stiff | Samo tam, kjer se moraš odločiti |
| `stepsProgress` 169 | %d od 7 korakov opravljenih | Stale count | %d od 3 korakov opravljenih |

Slovenian plural handling exists for photos, days, events (`Strings.count`, `photos`) but several format strings still bake in a count noun ("map: %d" `foldersCount`, "Obdržanih %d", "ostalih %d ostane"). Route those through `Strings.count` too.

## 7. Pro-grade interaction that fits this flow

Only items that serve "decide which of many near-identical frames and verify auto decisions".

| Id | Tool precedent | What to add | Where it fits | Eff |
|----|----------------|-------------|---------------|-----|
| A | Narrative Select, Lightroom Compare, Photo Mechanic Compare | **Compare mode**: 2-up (keeper vs candidate) or N-up of a moment, synced pan and zoom, jump to a person's face with Tab, 100% from the original, number keys 1 to 9 choose the keeper, X leaves out. Today only face crops are shown side by side. | Quick Review side panel (`QuickReview.swift:31-40`) and Selection moment detail; key `C` toggles | L |
| B | Lightroom 100% loupe, Photo Mechanic zoom | Real 100% zoom from the original under Z (F12), with the focus/subject box drawn | Quick Review, tray cell preview | M |
| C | Narrative Select focus overlay | "Why blurry" overlay: subject box and score from the quality pass, so the owner can overrule a verdict in seconds. Key `I` toggles info and overlay | Quick Review, Inspector | M |
| D | Photo Mechanic, Lightroom filters | Reason filter chips on trays and Quick Review: Eyes closed, Subject blurred, Movement, Screenshot, Left out by you. "Put back all with reason X" | Tray popover, Quick Review queue (`subset`) | M |
| E | Lightroom auto-advance, Narrative Select | Auto-advance after a decision in Selection (Return exists via `keepAndNext`), plus "next unresolved moment" key | `StepSelection.swift:78-83` | S |
| F | Any pro tool (history panel) | **Decisions log**: "The app decided N things, you changed M", list with undo per item. Gives trust and an audit trail for the automatic stage | New sheet from Stage header and Activity | M |
| G | Lightroom filmstrip | Filmstrip of moment frames under the Quick Review photo with the decision state, click to jump (replaces the single side column on narrow windows) | Quick Review bottom bar | M |

Not recommended here (outside the app's flow): star ratings and color labels, IPTC editing, ingest presets, tethering, develop adjustments.

## Suggested order

1. S batch (about 2 days): F1, F2, F5, F6, F15, F16, F17, F20, F22, F23, F28, F29, plus copy tables 6a to 6c.
2. M batch: F3, F7, F8, F9, F10, F13, F14, token files (`Tokens.swift`: spacing, radius, type, color, motion) with a Reduce Motion helper.
3. L batch: F4 (huge-count Stage), F11 (compare mode), then 7B to 7D, 7F.
4. Visual verification pass (all V items): contrast on real photos and glass, Stage at 3000 photos, Reduce Transparency, light mode, VoiceOver walk of Stage and Quick Review.

# M12b: design system, phase 1 (tokens and motion)

Goal: every screen from M13 to M18 is built from one source of spacing, radii, type, status colours and
motion, and Reduce Motion is handled in one place.

Files:
- `mac/Sources/CuratorCore/DesignTokens.swift`: the values as plain numbers (`SpaceScale`, `RadiusScale`,
  `MotionToken`, `MotionCurve`). No SwiftUI; tested in `mac/Tests/CuratorCoreTests/DesignTokensTests.swift`.
- `mac/Sources/PhotoCurator/DesignSystem/Tokens.swift`: `Space`, `Radius`, `TypeRole`, `StatusColor`.
- `mac/Sources/PhotoCurator/DesignSystem/Motion.swift`: `Motion.*`, `withMotion`, `.motionAnimation`.
- `scripts/check-design-tokens.sh` + `mac/design-tokens-baseline.txt`: ratchet against hardcoded values.

## Tokens

| Token | Value | Use |
|---|---|---|
| `Space.xxs / xs / s / m` | 2 / 4 / 6 / 8 | inside badges, chips, tight stacks |
| `Space.l / xl / xxl` | 12 / 16 / 20 | inside cards, between rows |
| `Space.xxxl / huge / giant` | 24 / 32 / 40 | page margins, between sections |
| `Radius.small / medium / large` | 8 / 12 / 16 | chips; thumbnails and inner buttons; photo tiles |
| `Radius.card / hero` | 22 / 26 | `.card()` default; hero cards on the album home |
| `TypeRole.pageTitle` | `.largeTitle.bold()` | page heading |
| `TypeRole.sectionTitle` | `.title2.weight(.semibold)` | section heading |
| `TypeRole.cardTitle` | `.headline` | card / row title |
| `TypeRole.body / supporting / label / caption` | `.body / .callout / .subheadline / .caption` | text |
| `TypeRole.counter` | system 34 bold rounded, monospaced digits | big numbers only |
| `TypeRole.heroSymbol` | system 44 | big symbol on hero and empty cards |
| `StatusColor.kept` | `.green` | in the album, kept |
| `StatusColor.removed` | `.red` | removed, blurry |
| `StatusColor.look` | `.orange` | "Have a look", the app asks |
| `StatusColor.stacked` | `.cyan` | near-identical frames stacked |
| `StatusColor.warning` | `.orange` | warnings, pending work |
| `StatusColor.accent` | `.accentColor` | accent |
| `StatusColor.removedFill` + `onRemoved` | dark red (0.72, 0.11, 0.11) + white, 6.5:1 | small "blurry" badges (M12c; white on system red is 3.5:1) |
| `StatusColor.onLook` | near black (white 0.1), 8:1 on orange | text or glyph on a solid `look` / `warning` fill (white on orange is 2.2:1) |
| `StatusColor.lookText` / `keptText` | dark amber / dark green in light mode, system orange / green in dark | coloured text on an 18% tint of its own colour (5.0:1 light, 5.7:1 dark); not inside views forced to dark |

`UndoToast` (DesignSystem/UndoToast.swift, M12c): the one confirmation for reversible actions. Call
`library.offerUndo(.putBack, count:)` (or `offerUndo(text)`) right after an action that registered its undo; the
toast's Undo calls the window's undo manager, so it matches Cmd+Z.

`ErrorBanner` (DesignSystem/ErrorBanner.swift, M12e): the one way to show an error. Call `library.report(error, retry:)`
(or build a `HumanError` with `humanError(...)` from CuratorCore); it shows a human sentence, the raw text behind
"Details", Try Again when `retry` is given, and Dismiss. It never times out and is announced to VoiceOver.
`floating: false` gives the tinted inline variant for cards (Export preview, export failure).

Status colours are system colours, so light and dark appearance both work. Decorative colours (stage
background blobs, AI glow gradient, step and person tints) are not status colours and stay where they are.

## Motion

| Name | Curve | When |
|---|---|---|
| `arrive` | spring 0.45 / 0.82 | something appears: photos fly in, a panel or row comes in |
| `settle` | spring 0.6 / 0.9 | things come to rest: overview, page / layout changes, progress |
| `drop` | spring 0.55 / 0.72 | something falls away (a photo into "Left out"); slower than first spec so the fall reads, faster than the old 0.8 |
| `stack` | spring 0.5 / 0.85 | frames slide onto the best one and into "Stacked" |
| `quick` | snappy 0.2 | hover, press, selection, small value changes |
| `fade` | easeInOut 0.2 | opacity only: image fade-in, a message or flash leaving, a reset |
| `sweep` | easeInOut 0.55 | the one-off scan band |
| `ambient` | easeInOut 9, repeating | slow background drift |

Reduce Motion: every motion becomes a 0.15 s cross-fade (never a spring); `sweep` and `ambient` become no
animation. Use:
- `.motionAnimation(.quick, value: x)` instead of `.animation(_, value:)` (reads the environment).
- `withMotion(.settle) { … }` instead of `withAnimation` (pass `reduceMotion:` from the view's
  `@Environment(\.accessibilityReduceMotion)` when you have it; otherwise the system setting is read).
- `Motion.animation(.quick, reduceMotion: reduceMotion)` when the view already reads the environment.
- `Motion.ambient` only after checking Reduce Motion is off.
- `.motionTransition(.move(edge: .top).combined(with: .opacity))` instead of `.transition(_:)` for anything that
  slides, pushes or scales (M12e): under Reduce Motion it becomes a cross-fade. Plain `.transition(.opacity)` is fine.

## Rules for new screens (M13 onwards)

1. No raw numbers for padding, spacing or corner radius: `Space.*`, `Radius.*`. If a value is missing, add a
   token (CuratorCore + test) instead of a one-off number.
2. Text uses `TypeRole.*`; fixed sizes only through `TypeRole.counter` / `heroSymbol`.
3. Status meaning uses `StatusColor.*`, never `.green` / `.orange` / `.red` directly.
4. Every animation is a `Motion` name. No `.spring(…)`, `.snappy`, `.easeOut(…)` or bare `withAnimation`.
5. Liquid Glass only on navigation and floating controls (AGENTS.md). Strings in `Strings.swift`, EN + SL.
6. `scripts/check-design-tokens.sh` must pass; counts may only go down.

## Migration plan (later PRs)

Phase 1 (this PR) migrated all animations (ratchet count 0) and the kept / removed / look / stacked status
colours. Paddings (156), corner radii (34) and fixed font sizes (20) are left as they are because the code
could not be compiled when this was written. Plan, one small PR each, compiled and checked by window capture:
1. Corner radii: map 8 / 12 / 16 / 22 / 26 to `Radius`; 10, 14, 18, 20, 24, 28 to the nearest token after a
   visual check. Then `.card(radius:)` defaults to `Radius.card`.
2. Paddings and stack spacings, screen by screen (Sorting stage, Album home, steps, Inspector, Settings);
   odd values (3, 5, 7, 9, 10, 14, 18, 22) go to the nearest token.
3. Fixed font sizes to `TypeRole`; symbol sizes that must stay fixed get named roles.
4. After each PR: `scripts/check-design-tokens.sh --update` to lower the baseline.

## Review keymap (M12d)

One keymap for Quick Review and its compare view: `ReviewKeymap` in `mac/Sources/CuratorCore/ReviewKeymap.swift`
(pure, tested in `ReviewKeymapTests.swift`). The view maps a key press to `ReviewKey`, asks
`ReviewKeymap.command(for:modifiers:in:)` and returns `.ignored` for anything that is not the review's, so VoiceOver,
menus and ⌘Z still get their keys (any key with ⌘, ⌥ or ⌃ is never the review's). The keys card is built from
`ReviewKeymap.entries(_:)`, so card and keys cannot drift.

Two key families (audit #18): the **review family** below acts on the one photo on screen; the **grid family**
(PhotoGrid, Selection: X, digits, Space = Quick Look, Esc clears the selection) acts on a selection and is documented
with the grid.

| Key | Quick Review (`.single`) | Compare (`.compare`) |
|---|---|---|
| → / ← | keep / leave out, next photo | next / previous frame on the right |
| ⌫ (and ⌘Z through the menu) | back, decision undone | (nothing) |
| Space | skip | (nothing) |
| 1 / 2 | (nothing) | left / right frame goes to the album (`LibraryModel.keep(group:photo:)`) |
| Z | toggle 100% of the original on the main face (drag to pan) | same, both panes in sync |
| F / E | favourite / faces large | (nothing) |
| C | open compare for this moment | close compare |
| ? | keys card | keys card |
| Esc | keys card, else close the review | keys card, else close compare |

Zoom (`ZoomMath`, `ReviewZoom.swift`): 100% = one image pixel on one screen pixel (`actualPixelsFactor`), centred on
the largest main face (`target`), clamped so no empty band shows (`clamp`/`offset`), drag moves the centre (`pan`).
The original is decoded with ImageIO off the main thread only for the photo on screen
(`PhotoCurator/ZoomablePhoto.swift`); zoom resets on a new photo, focus loss and scene-phase change.

## M12g: accessibility and copy (UX audit P2 rows 23 to 33)

- **Scaled display text** (#26): `.scaledFont(size, weight:, design:, relativeTo:)` (DesignSystem/Tokens.swift) is a
  `ScaledMetric`-backed replacement for `.font(.system(size:))` on text. Used for stage and page titles, the stage
  counters and the progress percent. Fixed `.system(size:)` stays only for decorative glyphs (hero symbols, flash
  icon, badge glyphs sized from the badge). Ratchet `fontSystemSize` 20 to 13. Not done (file owned by the motion
  pass): AlbumHome 42 / 26 pt hero and step titles (lines 69, 77, 135, 199, 320).
- **Dark stage decision** (#31): the Sorting Stage and Quick Review stay dark in every appearance (photos are judged
  on a dark surface; the stage glows are the product's look). `stageDarkSurface()` is the one place that forces it, so
  Quick Review and the Stage cannot drift. They respect Increase Contrast through `StageInk`: secondary text 0.78 to
  0.92 white, tile outlines 0.14 to 0.5, glow opacity 0.3 to 0.12, tray scrim 0.25 to 0.45 (0.7 with Reduce
  Transparency). System text styles (`.secondary`) already adapt. Hard-coded white opacities on the stage must use
  `StageInk`, not a literal.
- **Colour is never the only state** (#25): small stage tiles keep a 10 pt glyph for "to look at" and "left out"; with
  Differentiate Without Colour every state glyph shows at any size.
- **Engine codes without a translation** (#28): `LibraryModel.trCode(prefix, code, other:)` shows "Other reason" /
  "Other note" and logs the code (`Strings.codeText`, tested). Never show a raw engine code.
- **Default action key** (#32): `.defaultActionKey(if:)` / `.keyboardShortcut(.defaultAction)`: Next on the settled Stage
  (Resume / Analyse Again while those are the prominent action) and Align on the first pending clock lane.
- **Thumbnails** (#33): `ThumbnailCache.result(for:side:)` reports `.unreadable` ("Cannot read file") or `.noPreview`;
  `Thumbnail` shows the label (symbol only when the cell is too small), uses the cached 260 px image as a stand-in
  while a large one loads, and a spinner for sides above 520 (Quick Review).

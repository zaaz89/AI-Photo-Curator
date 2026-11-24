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

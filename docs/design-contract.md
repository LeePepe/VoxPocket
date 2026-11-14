# VoxPocket recorder design contract

## Design system & version

The recorder uses the repository-local `AppTheme`, semantic `Theme` palette and `BackgroundAtmosphere` implementation. There is no shared-design-system or DesignKit dependency in the resolved Presentation package; no design dependency is added. Native primitives target iOS 26+ and macOS 26+: `GlassEffectContainer`, interactive regular `glassEffect`, `glassEffectID`, SwiftUI sheets and native navigation. Both light and dark system appearances are required; do not force a global appearance.

This contract records the approved r3/v02 home behavior. It adds no CI workflow, gate exception, library version, or policy waiver. The full-width bottom-anchored recorder surface on desktop is a functional capture surface explicitly requested for this design, not a custom navigation/tab bar.

## Semantic token profile

| Role | Semantic token | Light meaning | Dark meaning |
| --- | --- | --- | --- |
| Canvas | `AppTheme.surfacePrimary` / `BackgroundAtmosphere` | Quiet light adaptive canvas | Quiet dark adaptive canvas |
| Text primary | `.primary` / `theme.palette.textPrimary` | Readable dark foreground | Readable light foreground |
| Text secondary | `.secondary` / `theme.palette.textSecondary` | Receding readable feedback | Receding readable feedback |
| Functional material | `.glassEffect(.regular.interactive())` | System optical material | System optical material |
| Reduced transparency | `.thickMaterial` | Legible solid-enough fallback | Legible solid-enough fallback |
| Acoustic accent | Semantic cyan/indigo system colors or existing theme tokens | Restrained live-level caustics | Restrained live-level caustics |

Use semantic tokens in business views, never hard-coded hex/RGB/RGBA colors. Group adjacent functional glass in one container; caustics belong beneath glass, not a second glass sampling layer. Do not apply functional glass to transcript/list content. No dependency or token-system migration is authorized.

## Required view states

Every state supports light and dark appearance, Reduce Motion and Reduce Transparency; icon controls have spoken labels and mobile hit areas at least 44 by 44 points. Dynamic Type, narrow widths and long CJK sentences must remain usable without clipped controls or truncated numeric values.

- `empty` / `idle`: one centered, borderless natural guide sentence; no home top status capsule, filter strip or raw-text panel. Upper normal portrait area targets 75–82 percent of the viewport, with scroll/accessibility fallback. Sentence is nominal rounded semibold 25 pt, 7 pt line spacing, -0.4 pt tracking, constrained readable width. Copy is disabled for placeholders.
- `populated` / `refined`: latest completed capture sentence remains visible when capture returns to idle, independently of history sorting/filtering. Tap finished text to copy and display lightweight feedback. Listening/refining placeholders must not enter the clipboard.
- `loading` / `recording`: immediate press-down capture; seven cyan/indigo bars and optical caustics respond to real audio level. At a held release, stop exactly once and use existing refinement. Processing displays immediate progress, ignores duplicate start/stop, and streams available refinement through the existing injected interfaces.
- `error`: readable failure with an accessible retry route; no silent failure and no user content in diagnostics. An interrupted or cancelled owned hold must not leave the microphone running.
- `fold`: bottom-leading 44-point icon-only glass Fold unfolds in place using stable glass IDs and the existing spring into Todo and Settings; main Fold becomes close. Narrow width may use an extra row within the same bottom surface, never clipped targets.
- `todo`: Todo and voice-note management, search/filter, detail, copy and existing note operations remain reachable in a native sheet/drawer. Settings remains reachable separately from the Fold entry. Closing either returns to the recorder.

Primary record button preserves view identity between idle and recording and identifiers `vox.record.button` / `vox.stop.button`; preserve `vox.transcript.final` and `vox.session.list`. Fold identifiers are `vox.fold.menu.button`, `vox.fold.todoList.button`, `vox.fold.settings.button`. Short tap and accessibility/keyboard activation remain start/stop toggles. Release while asynchronous start is pending is serialized and honored. No duplicate gesture/Button event may restart capture.

## Redlines & CI gate

All existing repository checks and independent exact-head review remain required. Do not weaken tests, skip verification or change CI/gate/policy files to satisfy this contract. Preserve unrelated regression tests and all privacy/concurrency/layering constraints. Source documentation and evidence do not substitute for actual SwiftUI rendering.

Use the pinned design auditor's supported interface (this revision has no `--audit-code`, `--audit-l10n`, `--check-edge-clipping` or `--audit-geometry` switches). Static source scan:

```sh
python3 .shared-ci/scripts/context/design_contract.py --root . --contract docs/design-contract.md \
  --ui-path Packages/VoxPresentation/Sources/UIShared/Views
```

Run rendered-matrix validation with `--visual --snapshot-dir <evidence-directory> --states idle,fold,recording,refined,todo --appearances light,dark` and the actual expected PNG pixel width(s). `--snapshot-dir` is the supported path option for external local evidence; do not mislabel it as `--screenshot-dir`, whose distinct in-root restriction is enforced by that check. Keep evidence outside Git, as repository protocol requires. Images must come from the actual current product views, use only synthetic data, and record build/head provenance. File existence/dimensions alone are not pixel acceptance: the independent reviewer must inspect the real PNGs and classify defects as IMPL_BUG or SPEC_GAP. If a desired audit is unsupported, report that limitation accurately and cover the behavior with native UI tests plus visual review rather than modifying the pinned tool or pretending the unsupported command passed.

The full Presentation tests, `scripts/verify`, and exact-head required PR CI/AI review must pass. If changed-mode verification selected no package work, explicitly run `scripts/verify --layer VoxPresentation` and report both results accurately.

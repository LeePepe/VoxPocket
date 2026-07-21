# Vox Island — Quick Recording Redesign

**Owner:** my-designer (design lead) · **Date:** 2026-07-21
**Component:** `QuickRecordingView` (macOS Quick Recording floating panel)
**Inspiration:** [CodeIsland](https://github.com/wxtsky/CodeIsland) — *its structure & interaction, not its skin.*

---

## 1. The one idea

Borrow CodeIsland's **Dynamic-Island grammar** — a single surface that **morphs
between a collapsed resting form and an expanded active form**, one continuous
shape, size and content animating together — and render it entirely in
**VoxPocket's existing premium glass language** (near-white frosted glass +
soft gemstone light-blobs, `BackgroundAtmosphere`). We keep the brand; we adopt
the *behavior*.

> We do **not** adopt CodeIsland's pixel-art / 8-bit mascot skin (clashes with
> the glass brand) and we do **not** anchor to the physical notch (works on any
> display, no notch-geometry fallbacks). The island floats top-center, where the
> pill already lives.

### What changes vs. today
| | Today | Vox Island |
|---|---|---|
| Shape | fixed 132×34 pill | one shape, **morphs** per state |
| Content | 1 line of trailing text | leading **waveform** + status label + live text, per-state layout |
| Legibility | ⚠️ white text on near-white glass | **dark ink** (`theme.textPrimary`) on light glass — fixed |
| Motion | color crossfade only | color crossfade **+ shape/size spring morph** |
| Structure | flat | collapsed ↔ expanded, like a Dynamic Island |

---

## 2. Geometry — one shape, five envelopes

The island is a single `Capsule`/rounded-rect whose **size is a function of
state**, animated with a spring. All envelopes are **top-anchored & centered**
inside a fixed transparent host panel sized to the largest envelope.

| State | W × H (pt) | Corner | Content |
|---|---|---|---|
| `idle` (resting) | 148 × 36 | 18 (capsule) | dot + “VoxPocket” wordmark, quietest |
| `listening` | 340 × 68 | 28 | ◗ waveform (live audio) · “正在聆听” · live text |
| `transcribing` | 340 × 68 | 28 | shimmer bars · “转写中” · live text |
| `refining` | 340 × 68 | 28 | shimmer bars · “润色中” · streamed refined text |
| `done` | 190 × 48 | 24 | ✓ check · “已粘贴” · then auto-collapse |
| `error` | 320 × 60 | 24 | ⚠ · error message (2-line clamp) |

**Host panel envelope** = `380 × 132` (max width + max height + top breathing).
The island animates *within* this transparent, shadowless panel. Panel stays a
fixed size; only the SwiftUI shape resizes — so no `NSPanel` re-layout churn.

Layout constants live in `QuickRecordingLayout` as an `islandSize(for:)` +
`islandCorner(for:)` pair (immutable, pure function of state).

---

## 3. Expanded internal layout (listening / transcribing / refining)

```
╭──────────────────────────────────────────────╮
│  ◗◗◗◗◗      正在聆听                             │   H=68
│  waveform   ─────────────  你好，我想说的是…      │
╰──────────────────────────────────────────────╯
   ▲ 44pt      ▲ status label (caption, tabular)
   leading     ▲ live text (footnote, head-truncated, left-fades)
```

- **Left cluster (44pt):** `VoxWaveform` — 5 bars driven by `audioLevel` spring
  (reuse the `BackgroundAtmosphere` spring integrator pattern). In
  transcribing/refining the bars become an indeterminate shimmer (no audio).
- **Status label:** `theme.typography.caption`, `theme.textSecondary`, the
  phase word (聆听/转写/润色). Uses the phase's status color as a 6pt leading dot.
- **Live text:** `footnote rounded medium`, `theme.textPrimary`, single line,
  `truncationMode(.head)`, left edge fades (keep the existing gradient mask).
- Insets: 14 leading / 16 trailing / vertical centered. 10pt gap waveform→text.

---

## 4. Materials & color (unchanged brand, corrected ink)

- **Background:** `BackgroundAtmosphere(status:audioLevel:)` — the exact same
  near-white glass + gemstone blobs + `.ultraThinMaterial`, clipped to the
  island shape. Its color center already morphs per state — that stays the
  motion backbone.
- **Border:** `Capsule/RoundedRectangle.strokeBorder(theme.strokeSubtle, 1)` —
  swap `Color.white.opacity(0.12)` (invisible on white) for the theme's
  `strokeSubtle` so the edge actually reads.
- **Ink (the fix):** all text uses `theme.textPrimary` / `textSecondary`
  (dark ink), **never white**. Light-mode Dynamic Islands are dark-on-light;
  this matches Apple and fixes the current white-on-white contrast bug.
- **Status accent:** the leading status dot + waveform tint pull from
  `theme.palette.status*` (listening/refining/done/error) — already defined.
- **Semantics fixed:** done = green, error = coral. Never repurposed.

No hardcoded hex added; everything routes through `Theme` + `AtmosphereGlass`.

---

## 5. Motion — the morph

Three coordinated, `reduceMotion`-aware layers:

1. **Shape morph:** `island size + corner` animate with
   `.spring(response: 0.42, dampingFraction: 0.82)` on `recorderStatus` change.
   One continuous shape stretches/settles — the Dynamic-Island feel.
2. **Color crossfade:** keep `BackgroundAtmosphere`'s existing 0.9s gemstone
   crossfade — unchanged.
3. **Content transition:** status label + text swap with
   `.opacity.combined(with: .move(edge: .bottom))`, `.animation` gated on
   `reduceMotion`. Waveform bars: live spring during listening; on
   transcribing/refining, a phase-shifted shimmer.
4. **Done → collapse:** on `.done`, show ✓ “已粘贴” for ~0.5s, then the shape
   springs down to the `idle` envelope as the window hides.

`reduceMotion`: no shape spring (snap), no shimmer, no waveform motion — static
bars at rest height. `BackgroundAtmosphere` already honors this.

---

## 6. New / changed files

| File | Change |
|---|---|
| `PlatformUI/QuickRecordingView.swift` | Rewrite: morphing island, per-state layout, dark ink, waveform cluster |
| `PlatformUI/QuickRecordingLayout.swift` | Add `islandSize(for:)`, `islandCorner(for:)`, expanded insets; keep `topInset` |
| `UIShared/Components/VoxWaveform.swift` | **New** — 5-bar audio/shimmer waveform, spring-driven, `reduceMotion`-safe |
| `VoxPocket/WindowManager.swift` | Panel sized to island **max envelope** (`380×132`); position note (top-center, `topInset`) |
| `QuickRecordingViewModel` | Expose `audioLevel: Double?` `@Published` for the waveform (bridge existing recorder level) |

**Out of scope (this pass):** notch anchoring, permission/action cards,
multi-session list (CodeIsland-only features VoxPocket has no source for yet).

---

## 7. Quality gate (definition of done)

- `swift build --package-path Packages/VoxPresentation` green.
- `swift test --package-path Packages/VoxPresentation` — `QuickRecordingLayoutTests`
  updated for the new size function; green.
- Contrast: live text (`textPrimary`) on lightest glass blob ≥ 4.5:1 (WCAG AA).
- `design-reviewer` agent on a rendered screenshot → /35 + P0/P1, no P0.
- No hardcoded color outside `Theme`/`AtmosphereGlass`. No white ink.

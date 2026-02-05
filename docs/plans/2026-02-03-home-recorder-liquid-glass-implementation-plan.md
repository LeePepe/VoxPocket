# HomeRecorderView + BackgroundAtmosphere Liquid Glass Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign `HomeRecorderView` and `BackgroundAtmosphere` with a minimal, Apple-2026-aligned liquid glass aesthetic, including iOS-only raw entry behavior and state-driven atmosphere.

**Architecture:** Keep existing view structure and state flow, but re-skin components with glass surfaces and refined typography. Background atmosphere remains a timeline-driven shader-like layer but with softer palettes and clearer light/dark shifts per status.

**Tech Stack:** SwiftUI, Swift, VoxPresentation UIShared components.

### Task 1: Prepare view layout logic for iOS raw behavior

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`

**Step 1: Add minimal layout test scaffolding**
- Not applicable (UI-only change). Instead, add TODO comments for manual verification targets (iOS compact vs regular, macOS).

**Step 2: Implement iOS raw-visibility logic**
- Add size class detection and `shouldShowRawPane` gating for iOS.
- Keep Raw entry in TopBar for iOS access.

**Step 3: Manual verification**
- Run the UI preview and confirm:
  - iPhone-size previews hide raw inline pane
  - iPad/macOS previews show raw inline pane

**Step 4: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift

git commit -m "refactor: gate raw pane by iOS size class"
```

### Task 2: Redesign HomeRecorderView visual language

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`

**Step 1: Update typography and spacing**
- Replace Avenir Next with system fonts, tune sizes/weights for a quiet hierarchy.

**Step 2: Introduce reusable glass surfaces**
- Add a lightweight glass background helper view or modifier.
- Apply to TopBar, refined pane, raw pane, and buttons.

**Step 3: Update button styles**
- Replace saturated button colors with softer, state-aware tints.
- Ensure press feedback is subtle (scale + opacity).

**Step 4: Manual verification**
- Preview for idle/listening/refining states to confirm hierarchy.

**Step 5: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift

git commit -m "feat: apply liquid glass styling to home recorder"
```

### Task 3: Redesign BackgroundAtmosphere

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift`

**Step 1: Adjust atmosphere configuration**
- Redefine state palettes with lighter idle + darker listening and gentle refinement tones.
- Tune breathing and energy responses.

**Step 2: Update rendering layers**
- Simplify inner shadows; add soft bloom + controlled vignette.
- Ensure minimal flicker and stable performance.

**Step 3: Manual verification**
- Run preview for all states and confirm light/dark shifts and calm motion.

**Step 4: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift

git commit -m "feat: refresh background atmosphere for liquid glass"
```

### Task 4: Final visual pass

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift`

**Step 1: Cross-check interaction states**
- Ensure Raw entry is visible on iOS and raw pane hides.
- Ensure top bar and controls are consistent in spacing and style.

**Step 2: Manual verification**
- Run previews for idle/listening/refining/done/error.

**Step 3: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift \
        Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift

git commit -m "chore: polish liquid glass visuals"
```

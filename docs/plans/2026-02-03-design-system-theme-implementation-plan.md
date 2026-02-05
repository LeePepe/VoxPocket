# Design System Theme + Tokens Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a lightweight Theme-based design system with color/font tokens and SwiftUI view modifier overloads, then apply it to HomeRecorderView and BackgroundAtmosphere.

**Architecture:** Add a `Theme` type with `Palette` and `Typography`, expose `ColorToken` and `FontToken`, then provide `View` extensions to map tokens to real values based on `ColorScheme`. Update UI components to use tokens instead of hard-coded colors/fonts.

**Tech Stack:** SwiftUI, Swift.

### Task 1: Introduce Theme + Token types

**Files:**
- Create: `Packages/VoxPresentation/Sources/UIShared/DesignSystem/Theme.swift`

**Step 1: Write the failing test**
- Not applicable (UI design system change). Mark as manual verification only.

**Step 2: Implement Theme and tokens**
- Define `ColorToken`, `FontToken` enums.
- Define `Theme` with `Palette` and `Typography`.
- Provide `Theme.current(for:)` to return light/dark theme.

**Step 3: Manual verification**
- Ensure tokens map to distinct values for light vs dark.

**Step 4: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/DesignSystem/Theme.swift

git commit -m "feat: add design system theme and tokens"
```

### Task 2: Add SwiftUI token modifiers

**Files:**
- Create: `Packages/VoxPresentation/Sources/UIShared/DesignSystem/View+Theme.swift`

**Step 1: Write the failing test**
- Not applicable (UI modifiers). Manual verification only.

**Step 2: Implement modifiers**
- Add `View.foregroundColor(_ token: ColorToken)` overload.
- Add `View.font(_ token: FontToken)` overload.
- Use `@Environment(\.colorScheme)` to select theme.

**Step 3: Manual verification**
- Sample view compiles with `.foregroundColor(.textPrimary)` and `.font(.title)`.

**Step 4: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/DesignSystem/View+Theme.swift

git commit -m "feat: add themed view modifiers"
```

### Task 3: Apply tokens to HomeRecorderView

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`

**Step 1: Replace hard-coded fonts/colors**
- Replace `Color.white.opacity(...)` with token-based `foregroundColor`.
- Replace `.font(.system(...))` with `.font(.title/.body/.caption)` tokens.

**Step 2: Manual verification**
- Preview in light/dark modes and check contrast.

**Step 3: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift

git commit -m "refactor: apply theme tokens to HomeRecorderView"
```

### Task 4: Apply tokens to BackgroundAtmosphere

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift`

**Step 1: Replace hard-coded colors where appropriate**
- Use theme palette for gradient/ambient base colors.
- Keep dynamic values for animation, but seed with tokens.

**Step 2: Manual verification**
- Preview for all recorder states in light/dark modes.

**Step 3: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift

git commit -m "refactor: apply theme tokens to background atmosphere"
```

### Task 5: Final polish

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/DesignSystem/Theme.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift`

**Step 1: Consistency sweep**
- Ensure all text colors and fonts use tokens.
- Ensure glass backgrounds align with theme palette.

**Step 2: Manual verification**
- Validate light/dark palettes and state transitions.

**Step 3: Commit**
```bash
git add Packages/VoxPresentation/Sources/UIShared/DesignSystem/Theme.swift \
        Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift \
        Packages/VoxPresentation/Sources/UIShared/Components/BackgroundAtmosphere.swift

git commit -m "chore: theme system polish"
```

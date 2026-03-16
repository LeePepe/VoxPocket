# Quick Recording Live Text Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live transcription text to the fixed-size quick recording panel, keeping the newest text visible on the right with a left-edge fade when content overflows.

**Architecture:** Reuse `QuickRecordingViewModel.liveTranscription` as the single source of truth and extend the existing `QuickRecordingView` with a compact text overlay. Keep layout constants centralized in `QuickRecordingLayout`, and verify behavior through focused `PlatformUITests`.

**Tech Stack:** SwiftUI, Combine, XCTest, Swift Package Manager

---

## Chunk 1: Tests And Layout Constants

### Task 1: Align layout tests with compact panel constants

**Files:**
- Modify: `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingLayoutTests.swift`
- Test: `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingLayoutTests.swift`

- [ ] **Step 1: Write the failing test expectations**

Update the quick recording layout assertions to match the compact pill currently defined in `QuickRecordingLayout`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingLayoutTests`
Expected: FAIL because the test still expects the previous larger panel constants.

- [ ] **Step 3: Write minimal implementation**

Adjust the test file only so the assertions match:

- `pillWidth == 132`
- `pillHeight == 34`
- `panelWidth == 164`
- `panelHeight == 58`

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingLayoutTests`
Expected: PASS

### Task 2: Add a regression test for retaining live text after stop

**Files:**
- Modify: `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingViewModelTests.swift`
- Test: `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test that starts recording, sends live transcription text, calls `stopRecording()`, and asserts `liveTranscription` still contains the last emitted text after stop completes.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingViewModelTests`
Expected: FAIL if the implementation clears live text too early.

- [ ] **Step 3: Write minimal implementation**

Keep `liveTranscription` intact through the stop/refine pipeline until the session resets on the next start.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingViewModelTests`
Expected: PASS

## Chunk 2: Quick Recording Panel Text Overlay

### Task 3: Add compact text layout constants

**Files:**
- Modify: `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingLayout.swift`
- Test: `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingLayoutTests.swift`

- [ ] **Step 1: Write the failing test**

Add assertions for any new padding or fade-width constants used by the text overlay.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingLayoutTests`
Expected: FAIL because the new constants do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Add small constants for:

- horizontal text inset
- left fade width

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingLayoutTests`
Expected: PASS

### Task 4: Render the live transcription overlay in the panel

**Files:**
- Modify: `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingView.swift`
- Test: `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingViewModelTests.swift`

- [ ] **Step 1: Write the failing test or assertion-driving change**

Use the view-model behavior test as the regression guard and update the view so it consumes `liveTranscription` under the intended states.

- [ ] **Step 2: Run targeted tests to establish a red state where applicable**

Run: `swift test --package-path Packages/VoxPresentation --filter QuickRecordingViewModelTests`
Expected: PASS after the regression guard exists; proceed with minimal view implementation using that verified behavior as the contract.

- [ ] **Step 3: Write minimal implementation**

Extend `QuickRecordingView` to:

- show a single-line text overlay only when `liveTranscription` is non-empty and the status is `listening`, `transcribing`, or `refining`
- align text to the trailing edge
- clip overflow without changing the panel size
- apply a left-edge fade mask

- [ ] **Step 4: Run focused tests**

Run: `swift test --package-path Packages/VoxPresentation --filter 'QuickRecording(Layout|ViewModel)Tests'`
Expected: PASS

## Chunk 3: Final Verification

### Task 5: Run package verification

**Files:**
- Test: `Packages/VoxPresentation`

- [ ] **Step 1: Run the relevant package tests**

Run: `swift test --package-path Packages/VoxPresentation`
Expected: PASS

- [ ] **Step 2: Review the diff**

Run: `git diff -- Packages/VoxPresentation docs/superpowers`
Expected: only the planned panel UI, tests, and docs changes.

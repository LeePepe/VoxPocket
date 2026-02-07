# Copy Buttons Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add copy actions so the main Copy button copies refined text and the Raw Transcript view provides a Copy Raw action.

**Architecture:** UIShared remains platform-agnostic by injecting copy closures into views. The app layer wires those closures to ClipboardService. Raw Transcript view gains a toolbar button with enabled/disabled state based on raw text.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest (SwiftPM packages).

### Task 1: Add UIShared tests for copy actions

**Files:**
- Create: `Packages/VoxPresentation/Tests/UISharedTests/CopyButtonsTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
import SwiftUI
@testable import UIShared

final class CopyButtonsTests: XCTestCase {
    func testBottomCopyInvokesHandler() {
        var didCopy = false
        let view = BottomControls(
            status: .idle,
            onStopOrRestart: {},
            onCopy: { didCopy = true },
            onNewSession: {}
        )

        // Trigger the action directly (unit-level intent test)
        view.onCopy()
        XCTAssertTrue(didCopy)
    }

    func testRawTranscriptCopyDisabledWhenEmpty() {
        let view = RawTranscriptView(rawText: "", status: .idle, canCopyRaw: false, onCopyRaw: {})
        XCTAssertFalse(view.canCopyRaw)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxPresentation --filter CopyButtonsTests` 
Expected: FAIL (RawTranscriptView initializer/signature doesn’t match; BottomControls action not exposed).

**Step 3: Commit**

```bash
git add Packages/VoxPresentation/Tests/UISharedTests/CopyButtonsTests.swift
git commit -m "test: add copy button coverage"
```

### Task 2: Wire bottom Copy to refined text

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketView.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketRootView.swift`
- Modify: `VoxPocket/VoxPocket/ContentView.swift`

**Step 1: Implement minimal wiring**

```swift
// HomeRecorderView: pass onCopy closure from parent
BottomControls(
    status: recorderStatus,
    onStopOrRestart: { ... },
    onCopy: { onCopyRefined() },
    onNewSession: { ... }
)
```

```swift
// VoxPocketView / VoxPocketRootView: provide onCopyRefined closure
let onCopyRefined = {
    clipboard.copy(viewModel.editorState.text)
}
```

**Step 2: Run tests**

Run: `swift test --package-path Packages/VoxPresentation --filter CopyButtonsTests` 
Expected: PASS

**Step 3: Commit**

```bash
git add Packages/VoxPresentation/Sources/UIShared/Views/HomeRecorderView.swift \
  Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketView.swift \
  Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketRootView.swift \
  VoxPocket/VoxPocket/ContentView.swift

git commit -m "feat: wire refined copy action"
```

### Task 3: Add Copy Raw to RawTranscriptView

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/RawTranscriptView.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketView.swift`
- Modify: `Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketRootView.swift`

**Step 1: Update RawTranscriptView API and toolbar**

```swift
struct RawTranscriptView: View {
    let rawText: String
    let status: RecorderStatus
    let canCopyRaw: Bool
    let onCopyRaw: () -> Void
    ...
    .toolbar {
        ToolbarItem(placement: .confirmationAction) {
            Button("Copy Raw", action: onCopyRaw)
                .disabled(!canCopyRaw)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
    }
}
```

**Step 2: Wire onCopyRaw from parent**

```swift
RawTranscriptView(
    rawText: viewModel.editorState.rawTranscription,
    status: viewModel.recorderStatus,
    canCopyRaw: !viewModel.editorState.rawTranscription.isEmpty,
    onCopyRaw: { clipboard.copy(viewModel.editorState.rawTranscription) }
)
```

**Step 3: Run tests**

Run: `swift test --package-path Packages/VoxPresentation --filter CopyButtonsTests` 
Expected: PASS

**Step 4: Commit**

```bash
git add Packages/VoxPresentation/Sources/UIShared/Views/RawTranscriptView.swift \
  Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketView.swift \
  Packages/VoxPresentation/Sources/UIShared/Views/VoxPocketRootView.swift

git commit -m "feat: add copy raw transcript"
```

### Task 4: End-to-end verify

**Files:**
- Modify: none

**Step 1: Manual check in app**

Run in Xcode: Build and run the macOS app. 
Expected: Bottom Copy copies refined text; Raw Transcript screen copies raw text; Copy Raw disabled when empty.

**Step 2: Final commit (if needed)**

```bash
git status --short
```
Expected: clean working tree.

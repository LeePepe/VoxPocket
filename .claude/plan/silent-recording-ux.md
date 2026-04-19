# Implementation Plan: Silent Recording UX Optimization

## Problem Summary

When a user stops a silent recording (no speech detected):
- **QuickRecordingViewModel**: Already handled — calls `onNoResult?()` which closes the panel
- **EditorViewModel**: Bug was fixed (skips refinement via `newTranscriptionAdded` guard), but **silently does nothing** — user gets no feedback about why nothing happened

## Goal

Add explicit user feedback when no speech is detected in EditorViewModel, matching QuickRecordingViewModel's quality level.

---

## Technical Solution

### Current flow (post-fix, EditorViewModel.stopRecording):
```swift
guard newTranscriptionAdded else {
    logger.log(.debug, "Skipping refinement: no new transcription content")
    return   // ← silent return, no feedback
}
await autoRefine()
```

### Proposed flow:
```swift
guard newTranscriptionAdded else {
    logger.log(.debug, "Skipping refinement: no new transcription content")
    snackbarService?.showWarning("未检测到语音内容")   // ← user feedback
    return
}
await autoRefine()
```

---

## Implementation Steps

### Step 1 — Add snackbar feedback on silent recording

**File**: `Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift`
**Location**: `guard newTranscriptionAdded` block in `stopRecording()`

Change:
```swift
guard newTranscriptionAdded else {
    logger.log(.debug, "Skipping refinement: no new transcription content from this recording session")
    return
}
```

To:
```swift
guard newTranscriptionAdded else {
    logger.log(.debug, "Skipping refinement: no new transcription content from this recording session")
    snackbarService?.showWarning("未检测到语音内容")
    return
}
```

`snackbarService` is `(any SnackbarService)?` — optional, already used elsewhere; `showWarning(_ message: String, action: SnackbarAction? = nil)` is confirmed to exist.

**Risk**: Low. No-ops if `snackbarService` is nil.

---

### Step 2 — Add unit test for silent-recording snackbar path

**File**: `Packages/VoxPresentation/Tests/UISharedTests/EditorViewModelSilentRecordingTests.swift` (new file)

Test scenario (analogous to `testStopRecordingWithEmptyTranscriptionTriggersNoResultCallback` in `QuickRecordingViewModelTests`):

```swift
// Given: EditorViewModel with FakeSnackbarService, empty liveTranscription
// When: stopRecording() is called after a silent recording (hadPreviousContent = false,
//       liveTranscription = "", commitCurrentTranscription produces empty text)
// Then: snackbarService received a .warning snackbar with message "未检测到语音内容"
//       AND autoRefine() was NOT called (no refinement state transition)

// Given: EditorViewModel with existing text (append mode), silent recording
// When: stopRecording() is called (liveTranscription = "")
// Then: snackbarService received a .warning snackbar
//       AND no new text was appended to the editor
```

**Note**: `EditorViewModel` has no existing test file — this is the first. Use `FakeRecordingUseCase`, `FakeTranscriptionUseCase`, `FakeEditingUseCase`, `FakeRefinementUseCase` (check `Packages/VoxPresentation/Tests/` for existing fakes).

---

### Step 3 — Build and verify

```bash
swift build --package-path Packages/VoxPresentation
swift test --package-path Packages/VoxPresentation --filter EditorViewModelSilentRecordingTests
```

---

## Key Files

| File | Operation | Description |
|------|-----------|-------------|
| `Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift` | Modify | Add `snackbarService?.showWarning(...)` in the silent-recording guard |
| `Packages/VoxPresentation/Tests/UISharedTests/EditorViewModelSilentRecordingTests.swift` | Create | Unit tests for the silent-recording snackbar path |

---

## Risks and Mitigation

| Risk | Mitigation |
|------|------------|
| `snackbarService` is nil in some contexts | Already optional (`?`) — safe, no-ops |
| Warning message language mismatch | Chinese matches codebase convention |
| **New-session mode: `commitCurrentTranscription()` throws or produces empty for non-speech reason** | `newTranscriptionAdded` will be `false`, snackbar fires. Pre-existing limitation; the warning is still correct from the user's perspective (nothing was transcribed). |
| **Very first recording of an empty session, user records in silence** | `currentText` is empty → `newTranscriptionAdded = false` → snackbar fires. This is correct UX: user recorded, nothing was heard. Intentional. |
| Auto-stop after silence fires the same path | Correct behaviour — auto-stop on silence should also notify the user |

---

## Out of Scope

- **Hybrid WhisperKit append-mode timing**: Apple Speech may produce no output but WhisperKit might later. EditorViewModel append mode does not await `finalResultPublisher`; this is a deeper architectural issue tracked separately.
- **Whitespace-only transcription**: Current guard uses `!newText.isEmpty`; whitespace-only is an edge case (rare in practice) and deferred.
- **State reset beyond the guard**: `stopRecording()` exits cleanly via the existing `return`; `isRecording` was already set to `false` at the top of the method. No additional state changes needed.

---

## SESSION_ID
- CODEX_SESSION: N/A
- GEMINI_SESSION: N/A

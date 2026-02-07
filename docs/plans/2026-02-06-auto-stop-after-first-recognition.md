# Auto-Stop After First Recognition Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure auto-stop by silence works for every recording session, not only the first one.

**Architecture:** Auto-stop is driven by live transcription updates from `TranscriptionCoordinator` through `DefaultTranscriptionUseCase` into `EditorViewModel`/`QuickRecordingViewModel`. We need to confirm where the signal stops after the first session (publisher completion vs. state reset), then keep the live stream active across sessions and reset view-model state between recordings.

**Tech Stack:** Swift, Combine, Swift Concurrency, XCTest (SwiftPM packages).

### Task 1: Reproduce and trace the data flow (root cause)

**Files:**
- Modify: none
- Read: `Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift`
- Read: `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift`
- Read: `Packages/VoxApplication/Sources/UseCases/DefaultTranscriptionUseCase.swift`
- Read: `Packages/VoxInfrastructure/Sources/TranscriptionKit/AppleSpeechTranscriber.swift`

**Step 1: Reproduce the bug in the app**

Run: `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' run`
Expected: First recording auto-stops; subsequent recordings do not auto-stop.

**Step 2: Capture the existing logs**

Observe logs for:
- `AppleSpeechTranscriber` error domain/code lines
- Any `Result received - isFinal` logs after the first session
Expected: Identify whether an error (and completion) happens when stopping or restarting.

**Step 3: Form the root-cause hypothesis**

Document one clear hypothesis, e.g.:
- H1: `liveResultPublisher` completes on a recoverable recognition error after the first session, so no further live updates arrive.
- H2: `liveText` is not reset between sessions, preventing auto-stop scheduling on new recordings.

### Task 2: Add a minimal failing test that reproduces the root cause

**Files:**
- Create: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/LiveResultStreamTests.swift`
- Create: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/TestDoubles/FakeTranscriptionCoordinator.swift`

**Step 1: Write a failing test for live-result continuity**

```swift
import XCTest
import Combine
@testable import TranscriptionKit

final class LiveResultStreamTests: XCTestCase {
    func testLiveResultPublisherDoesNotDieAfterRecoverableError() {
        let coordinator = FakeTranscriptionCoordinator()
        var values: [String] = []
        let cancellable = coordinator.liveResultPublisher
            .map(\.text)
            .sink(receiveCompletion: { _ in }, receiveValue: { values.append($0) })

        coordinator.emitLive(text: "first")
        coordinator.emitRecoverableError()
        coordinator.emitLive(text: "second")

        XCTAssertEqual(values, ["first", "second"], "Live results should continue after recoverable errors")
        cancellable.cancel()
    }
}
```

**Step 2: Run the test to confirm it fails**

Run: `swift test --package-path Packages/VoxInfrastructure --filter LiveResultStreamTests.testLiveResultPublisherDoesNotDieAfterRecoverableError`
Expected: FAIL (publisher completes after recoverable error, so "second" is missing).

### Task 3: Implement the root-cause fix (keep live stream alive)

**Files:**
- Modify: `Packages/VoxInfrastructure/Sources/TranscriptionKit/AppleSpeechTranscriber.swift`

**Step 1: Add a recoverable-error classification helper**

```swift
private func isRecoverableRecognitionError(_ error: NSError) -> Bool {
    // Treat cancellation/end-of-stream as recoverable; keep the stream alive.
    if error.domain == "kAFAssistantErrorDomain", error.code == 216 { return true }
    return false
}
```

**Step 2: Guard completion sending in the recognition callback**

```swift
if let error {
    let nsError = error as NSError
    self.logger.error("Recognition error: domain=\(nsError.domain), code=\(nsError.code), desc=\(nsError.localizedDescription)")
    if !isRecoverableRecognitionError(nsError) {
        self.liveResultSubject.send(completion: .failure(error))
    }
    self.stopInternal()
}
```

**Step 3: Run the failing test again**

Run: `swift test --package-path Packages/VoxInfrastructure --filter LiveResultStreamTests.testLiveResultPublisherDoesNotDieAfterRecoverableError`
Expected: PASS

### Task 4: Reset per-session live text in view models (defensive)

**Files:**
- Modify: `Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift`
- Modify: `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift`

**Step 1: Clear live text at the start of recording**

```swift
transcriptionUseCase.clearLiveText()
liveTranscription = ""
```

**Step 2: Add a regression test for repeated auto-stop**

**Files:**
- Create: `Packages/VoxPresentation/Tests/UISharedTests/EditorAutoStopTests.swift`
- Create: `Packages/VoxPresentation/Tests/UISharedTests/TestDoubles/FakeRecordingUseCase.swift`
- Create: `Packages/VoxPresentation/Tests/UISharedTests/TestDoubles/FakeTranscriptionUseCase.swift`

```swift
final class EditorAutoStopTests: XCTestCase {
    func testAutoStopTriggersAcrossMultipleSessions() async {
        let recording = FakeRecordingUseCase()
        let transcription = FakeTranscriptionUseCase()
        let editor = await EditorViewModel(
            recording: recording,
            transcription: transcription,
            editing: FakeEditingUseCase(),
            history: FakeHistoryUseCase(),
            refinement: FakeRefinementUseCase()
        )

        await editor.startRecording()
        transcription.emitLiveText("hello")
        try? await Task.sleep(for: .seconds(3))
        XCTAssertEqual(recording.stopCallCount, 1)

        await editor.startRecording()
        transcription.emitLiveText("world")
        try? await Task.sleep(for: .seconds(3))
        XCTAssertEqual(recording.stopCallCount, 2)
    }
}
```

**Step 3: Run UIShared tests**

Run: `swift test --package-path Packages/VoxPresentation --filter EditorAutoStopTests.testAutoStopTriggersAcrossMultipleSessions`
Expected: PASS

### Task 5: Verify end-to-end behavior

**Files:**
- Modify: none

**Step 1: Manual run**

Run: `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket -destination 'platform=macOS' run`
Expected: Each recording auto-stops after silence; no regression in first session.

**Step 2: Commit**

```bash
git add Packages/VoxInfrastructure/Sources/TranscriptionKit/AppleSpeechTranscriber.swift \
  Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift \
  Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/LiveResultStreamTests.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/TestDoubles/FakeTranscriptionCoordinator.swift \
  Packages/VoxPresentation/Tests/UISharedTests/EditorAutoStopTests.swift \
  Packages/VoxPresentation/Tests/UISharedTests/TestDoubles/FakeRecordingUseCase.swift \
  Packages/VoxPresentation/Tests/UISharedTests/TestDoubles/FakeTranscriptionUseCase.swift

git commit -m "fix: keep auto-stop working after first recording"
```

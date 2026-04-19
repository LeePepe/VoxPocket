---
title: "Streaming Long-Text Voice Input"
project: /Users/tianpli/Development/VoxPocket
branch: feat/azure-foundry-transcriber-model
status: draft
created: 2026-04-13
reviewed: false
review_rounds: 7
size: large
tasks:
  - id: T1
    title: "Add voice anchor + comprehensive lock to EditingUseCase"
    size: small
    parallel_group: 1
    executor: codex
    status: pending
  - id: T2
    title: "Add snapshotPublisher + snapshotGateActive to TranscriptionUseCase"
    size: medium
    parallel_group: 1
    executor: codex
    status: pending
  - id: T3
    title: "Add refineText (required method, no default) to RefinementUseCase"
    size: small
    parallel_group: 2
    executor: codex
    status: pending
  - id: T4
    title: "Implement DefaultStreamingInputCoordinator"
    size: large
    parallel_group: 3
    executor: codex
    status: pending
  - id: T5
    title: "Update QuickRecordingViewModel for streaming mode"
    size: medium
    parallel_group: 4
    executor: copilot
    status: pending
  - id: T6
    title: "Update EditorViewModel for streaming mode + manual-edit lock UI"
    size: medium
    parallel_group: 4
    executor: copilot
    status: pending
  - id: T7
    title: "Wire ServiceContainer with StreamingInputCoordinator"
    size: small
    parallel_group: 5
    executor: codex
    status: pending
---

# Background

VoxPocket supports single-shot voice recording today. This plan adds an incremental streaming pipeline so the transcriber can submit content continuously, LLM refinement runs on each snapshot, and results flow to clipboard and the input field in real time while preserving any manually-typed text before the voice region.

# Non-Negotiable Invariants

1. **Snapshot, not delta**: `snapshotPublisher` emits the full current transcript. Coordinator replaces `currentSnapshotText` on each event (never appends).
2. **Comprehensive voice zone lock**: Every `EditingUseCase` mutating method enforces the lock. Only `replaceVoiceZone` bypasses it.
3. **Explicit lock errors, never silenced**: Callers of `replaceAll`, `append`, `insert`, `delete`, `applyEdit` that receive a lock error must log it and handle it explicitly. No `try?` on any write that could be rejected by the lock.
4. **Atomic check-and-set for isStreaming**: `startStreaming()` reads and sets `isStreaming` in a single Mutex critical section. Second call returns early with no side effects.
5. **Gate closes before subscription cancel (drain first)**: `stopStreaming()` closes the gate (setting `snapshotGateActive = false`) BEFORE canceling the subscription. This routes any late `finalResultPublisher` events back to the legacy path (which queues a `replaceAll` — voice zone is still locked, so it fails with a logged error rather than silently losing the text). The coordinator then reads `lastCommittedText` from `DefaultTranscriptionUseCase` as the final raw fallback.
6. **Single subscription token**: `chunkCancellable: AnyCancellable?` in state; cancelled and nilled at the start of both `stopStreaming()` and `cancel()`.
7. **No LLM ghost streams**: Every `scheduleRefinement` call runs `refinementUseCase.cancel()` before starting a new task.
8. **Double-guarded writes**: Each refinement event loop checks `currentGeneration == gen` AND `!Task.isCancelled`.
9. **refineText has no default implementation**: Required protocol method; all conformers implement explicitly.
10. **Paste only at final stop**: `simulatePaste()` called once after `stopStreaming()` completes.

# Data Flow

```
TranscriptionCoordinator.finalResultPublisher
   │
   ▼ DefaultTranscriptionUseCase
   │  if snapshotGateActive: emit snapshot; update lastCommittedText; skip replaceAll
   │  else: replaceAll (surface errors, no try?); emit snapshot
   ▼ snapshotPublisher (full transcript snapshots)
   │
   ▼ DefaultStreamingInputCoordinator
   │  currentSnapshotText = snapshot (replace)
   │  scheduleRefinement(snapshot)
   │    → refinementUseCase.cancel()  ← kills ghost LLM stream
   │    → bump generation; cancel old task; start new Task
   │
   ▼ refineText(snapshot) → RefinementEvent.chunk
   │  guard gen == currentGeneration && !Task.isCancelled
   ▼ editingUseCase.replaceVoiceZone(with: text)  ← no lock check
   │
   ▼ refinedVoiceTextSubject → UI; clipboard on stopStreaming only
```

# Architecture Design

## T1 — EditingUseCase Voice Anchor + Lock

Protocol additions:
```swift
var voiceAnchorLocation: Int? { get }
var isVoiceZoneLocked: Bool { get }
func setVoiceAnchor(_ location: Int)
func clearVoiceAnchor()
func setVoiceZoneLocked(_ locked: Bool)
func replaceVoiceZone(with text: String) throws
```

`DefaultEditingUseCase` adds `private var _voiceAnchorLocation: Int? = nil` and `private var _isVoiceZoneLocked: Bool = false`.

Lock enforcement (all must throw a descriptive `VoxError` or `NSError`, not silently swallow):
- `replaceAll`: `guard !_isVoiceZoneLocked else { throw voiceZoneLockError() }`
- `append`: same guard
- `insert(_:at:)`: throw if `_isVoiceZoneLocked && location >= (_voiceAnchorLocation ?? Int.max)`
- `delete(range:)` and `applyEdit(range:newText:)`: throw if `_isVoiceZoneLocked && rangeOverlapsVoiceZone(range)`

`replaceVoiceZone(with text:)`: asserts anchor set; directly calls `textSubject.send()` — bypasses lock.

## T2 — TranscriptionUseCase Snapshot Gate

Protocol addition: `var snapshotPublisher: AnyPublisher<String, Never> { get }`.

`DefaultTranscriptionUseCase` additions:
- `private let snapshotSubject = PassthroughSubject<String, Never>()`
- `var snapshotGateActive: Bool` — backed by `OSAllocatedUnfairLock<Bool>(initialState: false)`, thread-safe get/set

Updated `finalResultPublisher` binding:
```swift
receiveValue: { [weak self] result in
    guard let self, !result.text.isEmpty else { return }
    let newText = result.text
    self.lastCommittedText = newText
    if self.snapshotGateActive {
        self.snapshotSubject.send(newText)  // coordinator consumes
        // replaceAll intentionally skipped in streaming mode
    } else {
        // Surface errors — no try?
        do {
            try self.editingUseCase.replaceAll(with: newText)
        } catch {
            self.logger.error("replaceAll failed: \(error)")
        }
        self.snapshotSubject.send(newText)
    }
}
```

## T3 — RefinementUseCase refineText

```swift
// Protocol — NO default implementation
func refineText(_ text: String, customPrompt: String?) -> AsyncThrowingStream<RefinementEvent, Error>
```

`DefaultRefinementUseCase` implements `refineText` like `refineStreaming` but with explicit `text` — constructs `RefinementRequest(text: text, ...)`, calls `llmService.refineStreaming(request)`, does NOT write to `editingUseCase`.

## T4 — DefaultStreamingInputCoordinator

### State

```swift
struct CoordinatorState {
    var currentSnapshotText: String = ""
    var currentGeneration: UInt64 = 0
    var isStreaming: Bool = false
    var currentTask: Task<Void, Never>? = nil
    var lastRefinedText: String = ""
    var chunkCancellable: AnyCancellable? = nil
}
private let state = Mutex<CoordinatorState>(CoordinatorState())
```

### startStreaming() — Atomic check-and-set

```swift
public func startStreaming() async {
    // Atomic check-and-set: single lock region prevents concurrent double-start
    let shouldStart = state.withLock { s -> Bool in
        if s.isStreaming { return false }
        s.isStreaming = true
        s.currentSnapshotText = ""
        s.currentGeneration = 0
        s.lastRefinedText = ""
        return true
    }
    guard shouldStart else { return }  // idempotent

    // Set voice anchor and lock
    editingUseCase.setVoiceAnchor(editingUseCase.currentText.count)
    editingUseCase.setVoiceZoneLocked(true)

    // SUBSCRIBE FIRST (PassthroughSubject: no events before subscription)
    let cancellable = transcriptionUseCase.snapshotPublisher
        .sink { [weak self] snapshot in
            guard let self else { return }
            self.state.withLock { $0.currentSnapshotText = snapshot }
            self.scheduleRefinement(snapshot: snapshot)
        }
    state.withLock { $0.chunkCancellable = cancellable }

    // Flip gate AFTER subscription installed — no snapshot can be missed
    transcriptionUseCase.snapshotGateActive = true
}
```

### scheduleRefinement(snapshot:)

```swift
private func scheduleRefinement(snapshot: String) {
    let gen: UInt64 = state.withLock { s in
        s.currentGeneration &+= 1
        s.currentTask?.cancel()
        s.currentTask = nil
        return s.currentGeneration
    }
    refinementUseCase.cancel()  // kill previous LLM stream

    let task = Task { [weak self, gen] in
        guard let self else { return }
        do {
            for try await event in self.refinementUseCase.refineText(snapshot, customPrompt: nil) {
                guard self.state.withLock({ $0.currentGeneration }) == gen,
                      !Task.isCancelled else { return }
                if case .chunk(let text) = event {
                    do {
                        try self.editingUseCase.replaceVoiceZone(with: text)
                    } catch {
                        self.logger.error("replaceVoiceZone failed: \(error)")
                        return
                    }
                    self.state.withLock { $0.lastRefinedText = text }
                    await MainActor.run { self.refinedVoiceTextSubject.send(text) }
                }
            }
        } catch { self.logger.error("refineText stream error: \(error)") }
    }
    state.withLock { $0.currentTask = task }
}
```

### stopStreaming() — Gate First, Then Drain

```swift
public func stopStreaming() async {
    // 1. Close gate FIRST: late finals route to legacy path (logged error, not silent drop)
    transcriptionUseCase.snapshotGateActive = false

    // 2. Cancel subscription and invalidate in-flight task (one lock region)
    let taskToAwait: Task<Void, Never>? = state.withLock { s in
        s.chunkCancellable?.cancel()
        s.chunkCancellable = nil
        s.currentGeneration &+= 1  // invalidate in-flight refinements
        let t = s.currentTask
        s.currentTask = nil
        return t
    }
    taskToAwait?.cancel()
    refinementUseCase.cancel()

    // 3. Await with 5s timeout
    if let task = taskToAwait {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: .seconds(5)); task.cancel() }
            _ = await group.next()
            group.cancelAll()
        }
    }

    // 4. Always unlock in defer
    defer {
        editingUseCase.setVoiceZoneLocked(false)
        state.withLock { $0.isStreaming = false }
    }

    // 5. Emit final text
    let finalText = state.withLock { s in
        s.lastRefinedText.isEmpty ? s.currentSnapshotText : s.lastRefinedText
    }
    await MainActor.run { refinedVoiceTextSubject.send(finalText) }
}
```

### cancel()

```swift
public func cancel() {
    transcriptionUseCase.snapshotGateActive = false
    state.withLock { s in
        s.chunkCancellable?.cancel(); s.chunkCancellable = nil
        s.currentGeneration &+= 1
        s.currentTask?.cancel(); s.currentTask = nil
        s.currentSnapshotText = ""; s.lastRefinedText = ""; s.isStreaming = false
    }
    refinementUseCase.cancel()
    editingUseCase.clearVoiceAnchor()
    editingUseCase.setVoiceZoneLocked(false)
}
```

## T5 — QuickRecordingViewModel

Optional `streamingCoordinator: (any StreamingInputCoordinator)?` (default nil = unchanged behavior).
- `startRecording()`: `await streamingCoordinator?.startStreaming()`
- Subscribe to `refinedVoiceTextPublisher` → update `refinedText` for display; no paste
- `stopRecording()`: `await streamingCoordinator?.stopStreaming()` → use `streamingCoordinator?.refinedVoiceText ?? rawTranscription` in `completeWithText()`
- `cancelRecording()`: `streamingCoordinator?.cancel()`

## T6 — EditorViewModel

Optional `streamingCoordinator: (any StreamingInputCoordinator)?`.
- Add `@Published var isVoiceZoneEditing: Bool = false` to `EditorViewModel` and `EditorViewState`
- `startRecording()`: start coordinator; set `isVoiceZoneEditing = true`
- `stopRecording()`: stop coordinator; set `isVoiceZoneEditing = false`
- `cancelRecording()`: cancel coordinator; set `isVoiceZoneEditing = false`
- `clearText()`: `editingUseCase.clearVoiceAnchor()`

## T7 — ServiceContainer

Instantiate `DefaultStreamingInputCoordinator` for main and quick stacks (macOS). Inject into view model factory methods.

# Required Acceptance Criteria Tests (T4)

1. Late final during stop: gate closed → late final routes to legacy (logged error); not silently lost
2. Recognizer revision: snapshot B replaces A; coordinator uses B as refinement input
3. Canceled-task stale write: after generation bump, no `replaceVoiceZone` called
4. Concurrent stop + snapshot: voice zone always unlocked
5. Double-start atomic: concurrent `startStreaming()` calls result in exactly one subscription
6. Rapid 5-snapshot burst: at most 1 active LLM stream at completion
7. start/stop/start: second start creates fresh subscription; no residual from first

# Subtask Details

## T1
**Files**: `Packages/VoxApplication/Sources/UseCases/EditingUseCase.swift`, `DefaultEditingUseCase.swift`
**Steps**: implement all APIs from Architecture Design T1; throw explicit errors (no silent swallow)
**Verification**: `swift build --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxApplication`

## T2
**Files**: `Packages/VoxApplication/Sources/UseCases/TranscriptionUseCase.swift`, `DefaultTranscriptionUseCase.swift`
**Steps**: implement snapshot gate as described; log (not swallow) replaceAll errors
**Verification**: `swift build --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxApplication`

## T3
**Files**: `Packages/VoxApplication/Sources/UseCases/RefinementUseCase.swift`, `DefaultRefinementUseCase.swift`
**Steps**: add required `refineText` with NO default; implement in DefaultRefinementUseCase using explicit text
**Verification**: `swift build --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxApplication`

## T4
**Files (new)**: `Packages/VoxApplication/Sources/UseCases/StreamingInputCoordinator.swift`, `DefaultStreamingInputCoordinator.swift`
**Steps**: implement exactly as described in Architecture Design T4
**Verification**:
```bash
swift build --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxApplication
swift test --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxApplication
```
All 7 acceptance criteria tests must pass.

## T5
**Files**: `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift`
**Verification**: `swift build --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxPresentation`

## T6
**Files**: `Packages/VoxPresentation/Sources/UIShared/ViewModels/EditorViewModel.swift`, `ViewStates/EditorViewState.swift`
**Verification**: `swift build --package-path /Users/tianpli/Development/VoxPocket/Packages/VoxPresentation`

## T7
**Files**: `VoxPocket/VoxPocket/ServiceContainer.swift`
**Verification**: `xcodebuild -project /Users/tianpli/Development/VoxPocket/VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build 2>&1 | tail -20`


# Local WhisperKit Core ML Transcriber Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 VoxPocket 中新增本地 WhisperKit(Core ML) 转录器，替换 Apple Speech 作为默认实时转录路径，并保留现有 Azure 路径作为可选回退。

**Architecture:** 在 `TranscriptionKit` 新增 `WhisperKitTranscriber`（实现 `TranscriptionCoordinator`），直接消费 `MicrophoneRecorder` 输出的 WAV 文件并生成 partial/final 事件。通过 `ServiceContainer` 按配置选择 `.localWhisperKit`。模型文件管理放在本地缓存目录，首版固定 `openai_whisper-large-v3-turbo`，后续再做可配置化。

**Tech Stack:** Swift 6.2, Swift Concurrency, Combine, WhisperKit, Core ML, XCTest

### Task 1: 引入 WhisperKit 依赖并建立可编译骨架

**Files:**
- Modify: `Packages/VoxInfrastructure/Package.swift`
- Create: `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`
- Test: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTranscriberCompileTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import TranscriptionKit

final class WhisperKitTranscriberCompileTests: XCTestCase {
    func testCanInstantiateWhisperKitTranscriber() {
        _ = WhisperKitTranscriber()
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitTranscriberCompileTests -v`
Expected: FAIL with missing type or missing package dependency

**Step 3: Write minimal implementation**

```swift
public final class WhisperKitTranscriber {
    public init() {}
}
```

并在 `Package.swift` 为 `TranscriptionKit` target 增加 WhisperKit 依赖。

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitTranscriberCompileTests -v`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/VoxInfrastructure/Package.swift \
  Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTranscriberCompileTests.swift
git commit -m "feat: add whisperkit transcriber skeleton"
```

### Task 2: 让 WhisperKitTranscriber 实现 TranscriptionCoordinator 协议

**Files:**
- Modify: `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`
- Test: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTranscriberBehaviorTests.swift`

**Step 1: Write the failing test**

```swift
func testProviderTypeIsWhisper() async throws {
    let sut = WhisperKitTranscriber()
    XCTAssertEqual(sut.speechRecognitionService.providerType, .whisper)
}
```

```swift
func testStartThenStopChangesState() async throws {
    let sut = WhisperKitTranscriber()
    try await sut.start(language: Locale(identifier: "zh-Hans"))
    XCTAssertTrue(sut.isTranscribing)
    await sut.stop()
    XCTAssertFalse(sut.isTranscribing)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitTranscriberBehaviorTests -v`
Expected: FAIL with unimplemented protocol members

**Step 3: Write minimal implementation**

在 `WhisperKitTranscriber` 中实现：
- `audioCaptureService/speechRecognitionService/finalResultPublisher/liveResultPublisher/audioLevelPublisher/isTranscribing`
- `start/stop/pause/resume`
- 内部 adapter（仿照 `AppleSpeechTranscriber` 的 internal service）

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitTranscriberBehaviorTests -v`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitTranscriberBehaviorTests.swift
git commit -m "feat: implement whisperkit transcription coordinator"
```

### Task 3: 接入模型加载与本地推理配置

**Files:**
- Modify: `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`
- Create: `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitConfig.swift`
- Test: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitConfigTests.swift`

**Step 1: Write the failing test**

```swift
func testDefaultModelIsLargeV3Turbo() {
    let config = WhisperKitConfig.default
    XCTAssertEqual(config.model, "openai_whisper-large-v3-turbo")
}
```

```swift
func testLocaleMapsToChineseLanguageHint() {
    XCTAssertEqual(
        WhisperKitConfig.default.languageHint(for: Locale(identifier: "zh-Hans")),
        "zh"
    )
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitConfigTests -v`
Expected: FAIL with missing config type

**Step 3: Write minimal implementation**

- 新增 `WhisperKitConfig`（model、computeUnits、预热开关、语言 hint 映射）
- 在 `start` 前懒加载模型；首版失败时抛出清晰错误并停止录音

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitConfigTests -v`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitConfig.swift \
  Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitConfigTests.swift
git commit -m "feat: add whisperkit model config and loader"
```

### Task 4: 把本地转录器接入应用配置与 DI

**Files:**
- Modify: `VoxPocket/VoxPocket/LLMAppConfig.swift`
- Modify: `VoxPocket/VoxPocket/ServiceContainer.swift`
- Test: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/TranscriberSelectionTests.swift`

**Step 1: Write the failing test**

```swift
func testDefaultProviderSelectsLocalWhisperKit() {
    XCTAssertEqual(LLMAppConfig.defaultTranscriberProvider, .localWhisperKit)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxInfrastructure --filter TranscriberSelectionTests -v`
Expected: FAIL with missing enum case or wrong selection

**Step 3: Write minimal implementation**

- `TranscriberProvider` 增加 `.localWhisperKit`
- `defaultTranscriberProvider` 调整为 `.localWhisperKit`
- `ServiceContainer.makeTranscriber()` 增加 `.localWhisperKit -> WhisperKitTranscriber()`
- 保留 `.appleSpeech/.hybridWhisper/.azureWhisper` 作为回退或调试选项

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxInfrastructure --filter TranscriberSelectionTests -v`
Expected: PASS

**Step 5: Commit**

```bash
git add VoxPocket/VoxPocket/LLMAppConfig.swift VoxPocket/VoxPocket/ServiceContainer.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/TranscriberSelectionTests.swift
git commit -m "feat: wire local whisperkit transcriber in service container"
```

### Task 5: 增加最小可观测性与失败回退策略

**Files:**
- Modify: `Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift`
- Modify: `Packages/VoxInfrastructure/Sources/Observability/TelemetryService.swift`
- Test: `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitFailureFallbackTests.swift`

**Step 1: Write the failing test**

```swift
func testModelLoadFailurePublishesErrorAndStops() async throws {
    let sut = WhisperKitTranscriber(config: .failingForTest)
    await XCTAssertThrowsErrorAsync {
        try await sut.start(language: Locale(identifier: "zh-Hans"))
    }
    XCTAssertFalse(sut.isTranscribing)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitFailureFallbackTests -v`
Expected: FAIL with missing error path

**Step 3: Write minimal implementation**

- 记录关键 telemetry 字段（模型名、加载耗时、RTF 粗指标、失败原因）
- 模型加载失败时立即停止并返回明确错误
- 不在该任务引入自动回退到 Apple（避免隐式行为）；仅记录建议

**Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/VoxInfrastructure --filter WhisperKitFailureFallbackTests -v`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/VoxInfrastructure/Sources/TranscriptionKit/WhisperKitTranscriber.swift \
  Packages/VoxInfrastructure/Sources/Observability/TelemetryService.swift \
  Packages/VoxInfrastructure/Tests/TranscriptionKitTests/WhisperKitFailureFallbackTests.swift
git commit -m "feat: add whisperkit telemetry and failure handling"
```

### Task 6: 回归验证与文档

**Files:**
- Modify: `Packages/VoxInfrastructure/OVERVIEW.md`
- Modify: `docs/architecture/packages-architecture.md`
- Create: `docs/transcription/local-whisperkit.md`

**Step 1: Write the failing doc check**

定义验收清单（人工）：
- 本地转录路径无网络调用
- 默认语言 `zh-Hans` 可产出可读文本
- 10 秒语音首次结果延迟 < 1.5s（开发机）

**Step 2: Run checks to verify gap**

Run:
- `swift test --package-path Packages/VoxInfrastructure`
- `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`
Expected: 先出现缺失文档/未完成项

**Step 3: Write minimal documentation**

文档包含：
- 模型下载与缓存目录
- 启动参数（model、computeUnits、语言）
- 常见失败与排查步骤

**Step 4: Run verification**

Run:
- `swift test --package-path Packages/VoxInfrastructure`
- `swift test --package-path Packages/VoxPresentation`
- `swift test --package-path Packages/VoxApplication`
- `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`
Expected: PASS

**Step 5: Commit**

```bash
git add Packages/VoxInfrastructure/OVERVIEW.md docs/architecture/packages-architecture.md \
  docs/transcription/local-whisperkit.md
git commit -m "docs: document local whisperkit transcription architecture"
```

## Notes

- 相关技能：`@superpowers:test-driven-development`, `@superpowers:verification-before-completion`
- YAGNI：首版不做模型切换 UI，不做多模型热切换。
- 风险：iOS 端模型体积和首轮加载时间；通过预热和缓存缓解。

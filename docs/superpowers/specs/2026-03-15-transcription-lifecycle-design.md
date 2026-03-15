# 转录生命周期事件设计

日期：2026-03-15

## 背景

当前快速录音（quick recording）的输出时机依赖 `QuickRecordingViewModel` 自己推断：

- 用户松手后先调用 `stopRecording()`
- 再短暂等待 `finalResultPublisher` 或 live text 收敛
- 然后立即提交转录、优化并输出

这个策略的问题是，UI 层并不知道底层转录器是否真的“识别完成”。它只能根据文本变化做启发式判断：

- `AppleSpeechTranscriber` 的 final 依赖系统回调，自然结束时机不由 UI 控制
- `WhisperKitTranscriber` 停止后会基于当前 best partial 合成 final，但没有向上暴露“流式识别已经真正结束”的独立信号
- `HybridWhisperTranscriber` 和 `AzureWhisperTranscriber` 也只暴露文本结果，没有统一的识别生命周期事件

因此，quick recording 在本地 Whisper 场景下可能出现“用户已松手，但尾部识别尚未收敛，UI 已经提前输出”的问题。

## 目标

建立统一的“转录生命周期事件”语义，让上层不再根据文本变化猜测状态，而是依赖 transcriber 明确发布的事件驱动流程。

本次目标：

- 为 transcriber 层新增统一 lifecycle event 流
- 统一各 provider 的“语音开始 / 静音 / 音频结束 / 识别完成”语义
- quick recording 改为等待 `松手 && recognitionCompleted` 后再输出
- 保留超时兜底，避免 provider 异常时用户界面卡死

非目标：

- 不重做全文编辑器（Editor）现有自动停录策略
- 不引入新的 provider 类型
- 不在 UI 层继续追加基于文本收敛的主流程判断

## 设计概览

在 `TranscriptionKit` 中新增统一事件类型：

```swift
public enum TranscriptionLifecycleEvent: Sendable, Equatable {
    case speechDetected
    case silenceDetected
    case audioEnded
    case recognitionCompleted
}
```

然后在 `TranscriptionCoordinator` 层新增 publisher：

```swift
var lifecycleEventPublisher: AnyPublisher<TranscriptionLifecycleEvent, Never> { get }
```

`TranscriptionUseCase` 仅透传该 publisher，不重新推导语义。UI 层只消费事件，不解释 provider 私有时序。

## 分层职责

### VoxInfrastructure

负责定义和发布生命周期事件。

每个 transcriber 需要保证：

- `speechDetected`：首次确认收到有效语音内容时发出
- `silenceDetected`：能够可靠检测尾部静音时发出；若 provider 无可靠静音概念，可以不发
- `audioEnded`：录音音频输入已结束时发出
- `recognitionCompleted`：不会再产生新的识别结果时发出

这里的关键语义是：`recognitionCompleted` 代表“本次转录已经结束”，不是“已经调用了 stop()”。

### VoxApplication

只做 publisher 透传，不二次判断 provider 行为。

### VoxPresentation

`QuickRecordingViewModel` 订阅 lifecycle 事件，并以 `recognitionCompleted` 作为 quick recording 输出的主判据。

## Provider 语义映射

### AppleSpeechTranscriber

- 在首次收到非空识别文本时发布 `speechDetected`
- `stop()` 中在音频输入结束后发布 `audioEnded`
- 系统返回 `isFinal == true` 的结果时发布 `recognitionCompleted`
- 如果系统任务以可接受的自然结束路径结束，且没有额外 final 回调，也需要保证最终发出 `recognitionCompleted`

说明：

- `stop()` 本身不能代表识别已完成，因为 Apple Speech 可能在 `endAudio()` 后仍继续处理尾部 buffer

### WhisperKitTranscriber

- 在首次收到有效 partial 时发布 `speechDetected`
- 若底层流可可靠判断静音尾段，则发布 `silenceDetected`；如果没有稳定来源，可以暂不发
- `stop()` 调用底层 `stopStreaming()` 后发布 `audioEnded`
- 底层流真正收尾、最终文本稳定并且 final 已对外发布后，再发布 `recognitionCompleted`

说明：

- 这里必须把 `recognitionCompleted` 放在 provider 内部定义，而不是让 UI 基于 live text 停止变化去猜

### HybridWhisperTranscriber

- Apple Speech 阶段首次收到有效文本时发布 `speechDetected`
- 录音停止、音频输入结束时发布 `audioEnded`
- Whisper 批量转录完成并发布 final 后，发布 `recognitionCompleted`
- 若 Apple Speech 全程无内容而跳过 Whisper，也要在该分支上结束时发出 `recognitionCompleted`

### AzureWhisperTranscriber

- 如未来支持显式语音检测，可在首次确认语音内容后发布 `speechDetected`
- 现有 RMS 静音检测命中自动停录阈值时发布 `silenceDetected`
- 录音停止时发布 `audioEnded`
- Whisper API 返回最终文本或确认本次转录结束时发布 `recognitionCompleted`

### LoadingFallbackTranscriptionCoordinator

只透传当前 active coordinator 的 lifecycle 事件，不合并多路，不重新解释事件语义。

## Quick Recording 行为调整

`QuickRecordingViewModel.stopRecording()` 的主流程调整为：

1. 用户松手，调用 `recordingUseCase.stopRecording()`
2. ViewModel 进入 `.transcribing`
3. 等待 `transcriptionUseCase.lifecycleEventPublisher` 发出 `.recognitionCompleted`
4. 收到事件后读取当前最终转录，执行 `commitCurrentTranscription()`
5. 进入 refinement 流程
6. refinement 完成后 paste / onComplete

### 超时兜底

为了避免 provider 异常、publisher 漏发或系统 API 时序异常导致流程卡死，保留一个超时兜底：

- 等待 `recognitionCompleted` 的最大时长为 2.5 秒
- 超时后使用当前最佳可得文本继续流程
- 若当前文本仍为空，则走 `onNoResult`

超时只是 fallback，不再是主流程判据。

## 数据流

### 开始录音

1. quick recording 开始录音
2. transcriber 开始发 live text
3. transcriber 按 provider 能力发出 `speechDetected`

### 松手结束

1. 用户松手
2. `QuickRecordingViewModel.stopRecording()` 调用 `recordingUseCase.stopRecording()`
3. transcriber 发出 `audioEnded`
4. transcriber 继续完成尾部识别
5. transcriber 发布最终结果
6. transcriber 发出 `recognitionCompleted`
7. ViewModel 提交文本并进入 refinement

### 异常/兜底

1. 用户松手
2. stop 正常执行，但 provider 未按预期发出 `recognitionCompleted`
3. ViewModel 等待最多 2.5 秒
4. 超时后使用当前最佳文本继续

## 错误处理

- 如果 transcriber 发布了空 final 且同时完成事件到达，ViewModel 仍应按“无结果”处理
- 如果 provider 同时发布 final 和 `recognitionCompleted`，顺序应保证上层读取到的文本已经是最终版本
- 如果 provider 因错误提前终止，也应尽量发出一次 `recognitionCompleted` 或由上层超时兜底结束
- `LoadingFallbackTranscriptionCoordinator` 切换 active provider 后，不应泄露非活动 provider 的 lifecycle 事件

## 测试策略

### TranscriptionKitTests

新增或调整测试，验证：

- `AppleSpeechTranscriber` 在识别自然完成时会发出 `recognitionCompleted`
- `WhisperKitTranscriber` 停止后在 final 对外可见后发出 `recognitionCompleted`
- `HybridWhisperTranscriber` 在 Whisper 批量转录结束后发出 `recognitionCompleted`
- `AzureWhisperTranscriber` 在静音自动停录和批量转录结束路径上分别发出对应 lifecycle 事件

### LoadingFallbackTranscriptionCoordinatorTests

验证：

- lifecycle 事件只来自当前 active coordinator
- provider 切换后旧 provider 的事件不会串到上层

### UseCasesTests

验证：

- `DefaultTranscriptionUseCase` 会透传 lifecycle 事件，不篡改顺序和语义

### PlatformUITests

验证：

- quick recording 在用户松手后不会立即完成
- 只有收到 `.recognitionCompleted` 才会进入 refinement / paste
- 如果 lifecycle 事件缺失，会在 2.5 秒后用最新文本兜底
- 如果最终文本为空，会触发 `onNoResult`

## 风险与权衡

### 为什么不继续让 ViewModel 猜测文本收敛

这种方案改动最小，但职责是错的：

- UI 并不知道 provider 是否还有尾部处理
- 文本静默不等于识别已完成
- provider 行为一旦变化，UI 推断逻辑就会再次失真

因此本次选择把“完成判定”收回到 transcriber 层。

### 为什么仍然保留超时

跨 provider、跨系统 API 的异步流程无法保证绝对完美。完全移除超时会把偶发漏事件放大为用户可见卡死，因此仍保留 2.5 秒兜底。

## 实施顺序

1. 在 `TranscriptionKit` 定义 `TranscriptionLifecycleEvent`
2. 为 `TranscriptionCoordinator` 增加 lifecycle publisher
3. 更新四个 transcriber 与 fallback coordinator
4. 在 `TranscriptionUseCase` / `DefaultTranscriptionUseCase` 透传 publisher
5. 更新 `QuickRecordingViewModel`，改用 `recognitionCompleted` 驱动 stop 后流程
6. 补充和修正单元测试

## 验收标准

- quick recording 在 local whisper 路径下不会在松手瞬间提前输出
- quick recording 的输出条件变为 `松手 && recognitionCompleted`，而不是 live text 收敛
- 各 transcriber 对外提供统一 lifecycle 事件语义
- 测试覆盖 provider 事件发布、fallback 透传、quick recording 等待逻辑和超时兜底

---
layer: VoxApplication
role: UseCases 业务编排 —— 把领域与基础设施组装成录音/转写/精炼/会话流程
depends_on: [VoxDomain, VoxInfrastructure]
depended_by: [VoxPresentation]
red_lines:
  - 只能依赖 VoxDomain/VoxInfrastructure(+ 外部 LokiKit);禁止 import VoxPresentation(宪法 II)
  - 遥测事件只带指标(duration/count/source/session_id),严禁带转写/精炼文本内容(宪法 IV)
  - 共享可变状态用 Mutex<State> 守护;@MainActor 用于 UI 契约;禁止主线程阻塞(宪法 III)
  - 依赖协议而非具体类型;默认实现命名 Default*(宪法 Additional Constraints)
roles:
  Types:   [RecordingUseCase, TranscriptionUseCase, RefinementUseCase, SessionUseCase, EditingUseCase, HistoryUseCase, StreamingInputCoordinator, DeepLinkAction]
  Service: [DefaultRecordingUseCase, DefaultTranscriptionUseCase, DefaultRefinementUseCase, DefaultSessionUseCase, DefaultEditingUseCase, DefaultHistoryUseCase, DefaultStreamingInputCoordinator, InMemorySessionUseCase, DeepLinkRouter]
test: swift test --package-path Packages/VoxApplication
owns: [UseCases]
---

# VoxApplication Tech Context

## 职责
应用层(单 target `UseCases`)。协议 + `Default*` 实现的业务编排:
- **RecordingUseCase / TranscriptionUseCase / RefinementUseCase**:录音→转写→精炼主链。
  `DefaultTranscriptionUseCase` 桥接 `TranscriptionCoordinator` 到两个 publisher
  (`liveTextPublisher` 实时可变 / `finalResultPublisher` 稳定一次)。
- **SessionUseCase**:会话生命周期。`ProxySessionUseCase` 包裹任意实现,运行时热切换
  `InMemorySessionUseCase` → `SwiftDataSessionUseCase`(不改调用点)。
- **EditingUseCase / HistoryUseCase**:文本编辑与 patch 撤销/重做。
- **StreamingInputCoordinator**:流式输入协调。

## 依赖
- **仓库内**:`VoxDomain` + `VoxInfrastructure`(TranscriptionKit/LLMKit/Persistence/PlatformAdapters)。
- **外部**:`LokiKit`(遥测)。所有 UseCase 的 telemetry 参数默认 `NoopTelemetryService`。

## 约束 / 红线投影
- 遥测:`recording.stopped`(duration_s)、`transcription.completed`(word_count/source)、
  `refinement.completed/failed`(duration_ms)、`session.created/deleted`(session_id)——**无内容**。
- 并发:`Mutex<State>` 守护状态;`@unchecked Sendable` 仅限 Combine 桥接且需注明理由。

## 层内轴
`Types`(协议:`*UseCase`.swift 等)不得依赖 `Service`(`Default*` 实现);实现依赖协议合法。

---
layer: VoxInfrastructure
role: 转写 · LLM · 持久化 · 平台适配 · 偏好 —— 对接外部系统与框架的适配层
depends_on: [VoxDomain]
depended_by: [VoxApplication, VoxPresentation]
red_lines:
  - 只能依赖 VoxDomain(+ 外部 LokiKit);禁止 import VoxApplication/VoxPresentation(宪法 II)
  - API key/secret 必须来自环境变量,禁止硬编码;启动即校验、缺失快速失败(宪法 V)
  - 转写文本/音频/精炼内容禁止写入日志或遥测负载,遥测只带指标(宪法 IV)
  - 端点/资源标识来自 config/env,禁止硬编码 Microsoft/Azure 标识(宪法 V)
  - 主线程禁止阻塞调用(Thread.sleep/同步 I/O);流式用 AsyncThrowingStream(宪法 III)
roles:
  Types:   [Protocols, Models]
  Config:  [Preferences]
  Repo:    [Persistence, PlatformAdapters, Providers]
  Service: [Services, Utilities, LLMKit, TranscriptionKit]
test: swift test --package-path Packages/VoxInfrastructure
owns: [TranscriptionKit, LLMKit, Persistence, PlatformAdapters, Preferences]
---

# VoxInfrastructure Tech Context

## 职责
基础设施/适配层。五个 target,分别对接不同外部系统:
- **TranscriptionKit**:语音识别(AppleSpeech / WhisperKit / Azure Whisper),`TranscriptionCoordinator`。
- **LLMKit**:LLM 服务与 provider(`AppleIntelligenceProvider` 等),流式 `RefinementEvent`。
- **Persistence**:SwiftData 会话存储(`SessionRepository` / `SwiftDataSessionRepository`)。
- **PlatformAdapters**:macOS 系统集成(Clipboard / Accessibility / GlobalHotkey / ClaudeInbox),
  每个都有跨平台协议 + `MacOS*` 实现。
- **Preferences**:用户偏好,无依赖。

## 依赖
- **仓库内**:仅 `VoxDomain`(CoreModels/TextHistory)。
- **外部**:`LokiKit`(`../../../LokiKit`,遥测/日志)+ `swift-async-algorithms` + `WhisperKit`。
  LokiKit 不进 `depends_on`(它不在本仓库,防腐脚本只校验本地 layer)。

## 约束 / 红线投影
- **secrets**:`whisperkey` / `kimikey`·`AZURE_API_KEY` / `LOKI_TOKEN` 全来自 env,启动校验。
- **隐私**:遥测事件只带 duration/count/source/session_id,**绝不带内容**。
- **供应商卫生**:无硬编码 Azure/Microsoft 标识;端点走 config。

## 层内轴
`Types(Protocols/Models)` ← `Config(Preferences)` ← `Repo(Persistence/PlatformAdapters/Providers)`
← `Service(LLMKit/TranscriptionKit/Services/Utilities)`。低角色不得 import 高角色。

## 测试注意
`swift test` 会一起编译本包所有 test target;某个 target 的既有失败会阻塞其他 target 运行
(见 CLAUDE.md)。定位单类用 `--filter`。

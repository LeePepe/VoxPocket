---
layer: VoxKit
role: 独立语音 SDK(VoxCore, VoxSpeech, VoxSpeechWhisperKit, VoxRefine, VoxLLM, VoxWorkflow)
owns: ["Packages/VoxKit/**"]
depends_on: []
gate: {check: "python3 scripts/gates/check_frontmatter.py"}
red_lines:
  - 严禁读取环境变量、UserDefaults、Bundle、Keychain 或未注入路径(R1)
  - 严禁依赖 LokiKit、shared-telemetry 或任何外部遥测库(R2)
  - 日志与遥测只允许 StaticString 消息与类型化 VoxLogField,严禁包含语音、转写或精炼文本(R3)
  - 公共 API 只允许 async/await 与 AsyncStream/AsyncThrowingStream,严禁暴露 Combine 或逃逸回调(R4)
  - 严禁包含产品名路径(VoxPocket)、内部工单号或非 example Azure 主机名(R5)
---

# VoxKit Tech Context

Last-Reviewed: 2026-11-05

VoxKit 是零宿主耦合的独立 SwiftPM 语音与精炼 SDK 层。

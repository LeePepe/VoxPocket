# VoxInfrastructure overview

Purpose
- Platform services and adapters: LLM, transcription, persistence, platform integration, and preferences. Observability now lives in the standalone `LokiKit` package.

Public products
- `TranscriptionKit`
- `LLMKit`
- `Persistence`
- `PlatformAdapters`
- `Preferences`

Depends on
- VoxDomain (`CoreModels`, `TextHistory`)
- LokiKit
- Swift Async Algorithms
- WhisperKit (Core ML 本地语音转录)

Primary entry points
- `Packages/VoxInfrastructure/Package.swift`
- `Packages/VoxInfrastructure/Sources/LLMKit/`
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/`
- `Packages/VoxInfrastructure/Sources/Persistence/`
- `Packages/VoxInfrastructure/Sources/PlatformAdapters/`
- `Packages/VoxInfrastructure/Sources/Preferences/`

Recommended read order
1) `Packages/VoxInfrastructure/Package.swift`
2) `Packages/VoxInfrastructure/Sources/LLMKit/`
3) `Packages/VoxInfrastructure/Sources/TranscriptionKit/`
4) `Packages/VoxInfrastructure/Sources/Persistence/`
5) `Packages/VoxInfrastructure/Sources/PlatformAdapters/`
6) `Packages/VoxInfrastructure/Sources/Preferences/`
7) `~/Development/LokiKit/`

Notes for LLM context
- Start with service boundaries and protocols, then implementations.

Transcription defaults
- 默认实时转录路径为 `HybridLocalWhisperTranscriber`（`hybridLocalWhisper`），由 Apple Speech 提供实时文本、WhisperKit 提供停止后的最终增强。
- `AppleSpeechTranscriber`、`HybridWhisperTranscriber`、`AzureWhisperTranscriber` 作为回退/调试路径保留。
- 本地模型配置入口在 `LocalWhisperKitConfig`，包含模型名、预加载开关、语言提示映射。

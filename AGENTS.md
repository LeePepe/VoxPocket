# AGENTS.md

Last-Reviewed: 2026-03-31

## Project Snapshot

VoxPocket 是 macOS/iOS 的 SwiftUI 语音转写应用，默认语音识别语言为 `zh-Hans`，并支持 Apple Intelligence 文本精炼。

## Layered Architecture

```
VoxPresentation  ->  VoxApplication  ->  VoxInfrastructure  ->  VoxDomain
```

- `VoxDomain`: 纯领域模型（`CoreModels`, `TextHistory`）
- `VoxInfrastructure`: 转写、LLM、持久化、可观测性、平台适配
- `VoxApplication`: UseCases 业务编排
- `VoxPresentation`: SwiftUI 视图与 ViewModel

## Start Here

- Fast index: `docs/index.md`
- Records index (source of truth map): `docs/records/index.md`
- Architecture docs: `docs/architecture/`
- Harness baseline: `docs/harness/metrics-baseline.md`

## Build And Test

```bash
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build
swift build --package-path Packages/VoxDomain
swift test --package-path Packages/VoxPresentation
swift test --package-path Packages/VoxApplication
```

## Engineering Rules

- 协议驱动 DI，默认实现用 `Default*` 命名。
- 测试替身使用 `Fake*` / `Mock*` 命名。
- 不向 `VoxDomain` 引入外部依赖。
- 变更前后优先保持分层依赖方向不变。

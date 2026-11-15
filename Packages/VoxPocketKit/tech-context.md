---
layer: VoxPocketKit
owns:
  - Packages/VoxPocketKit/**
depends_on: [VoxDomain]
roles:
  Types: [Types]
  Repo: [Audio, Transport]
  Service: [Ingest]
gate: {build: "swift build --package-path Packages/VoxPocketKit --explicit-target-dependency-import-check error", test: "swift test --package-path Packages/VoxPocketKit --explicit-target-dependency-import-check error"}
red_lines:
  - 只能依赖 VoxDomain，不得向上依赖应用层或基础设施层
  - 录音、转写与标题内容不得写入日志或遥测
  - 外部传输元数据必须校验 UUID、版本、时长、格式、路径和大小
---

# VoxPocketKit layer context

`VoxPocketKit` is the cross-platform Watch capture and receipt module. Its app-facing seams
are `WatchAudioCapturing`, `WatchSyncTransport`, and `WatchTodoIngestion`; production adapters
remain conditional on Apple frameworks while tests use injected actors.

Storage is injected by the app shell: audio and `sender.json` share the Watch sandbox
storage directory; the phone inbox uses UUID directories with `metadata.json` and AAC
files. A metadata-first staging directory and atomic audio/directory renames recover
callback arrivals even before app readiness. Sender audio is retained until a durable
`todoAdded` receipt; failures are retryable and do not overwrite the original recording.

`FileWatchIngestPersistence` persists pending jobs and successful completions only,
including migration of the prior typed `watch-state.json` journal. Microphone permission
callbacks are once-guarded, cancellable and bounded rather than holding startup forever.
The coordinator validates owned inbox paths, serializes each capture ID across actor
reentrancy, and preserves work on cancellation. The app supplies Speech, refinement,
startup/background lifetime and the existing Todo-use-case adapter; this package never
imports an upper application layer.

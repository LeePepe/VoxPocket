---
id: VoxKit
layer: VoxKit
owns: [Packages/VoxKit/**]
depends_on: []
gate: {build: "swift build --package-path Packages/VoxKit --explicit-target-dependency-import-check error", test: "swift test --package-path Packages/VoxKit --explicit-target-dependency-import-check error", check: "Packages/VoxKit/scripts/redlines/check.sh --self-test"}
red_lines: ["R1 SDK has no environment, file, configuration, defaults, bundle, or keychain reads; storage is injected", "R2 no LokiKit, shared-telemetry, or external path dependencies", "R3 StaticString structured logging and telemetry carry metrics/labels only; canary tests prove no content leaks", "R4 public APIs use async/await and AsyncStream/AsyncThrowingStream; no Combine or escaping callbacks", "R5 no product-name paths, internal issue IDs, or non-example Azure hosts"]
roles:
  Types: [VoxCore, VoxRefine]
  Config: [VoxStorageLocations, LocalWhisperKitConfig]
  Service: [VoxSpeech, VoxSpeechWhisperKit, VoxLLM, VoxWorkflow, VoxWorkflowWhisperKit]
test: swift test --package-path Packages/VoxKit --explicit-target-dependency-import-check error
targets: [VoxCore, VoxSpeech, VoxSpeechWhisperKit, VoxRefine, VoxLLM, VoxWorkflow, VoxWorkflowWhisperKit, VoxCoreTests, VoxSpeechTests, VoxSpeechWhisperKitTests, VoxRefineTests, VoxLLMTests, VoxWorkflowTests, CanaryTests, GoldenTraceTests]
Last-Reviewed: 2026-11-06
---

# VoxKit Tech Context

`VoxKit` is the standalone SDK boundary. `VoxCore` contains dependency-free public
contracts and safe value types; hosts inject credentials, logging, telemetry, and storage.
The package must remain independent from VoxDomain, LokiKit, shared-telemetry, and the app.

## Phase 2 modules

- `VoxCore`: shared immutable values, async speech/session contracts, logging, credentials and storage injection.
- `VoxSpeech`: Apple speech, Azure batch/realtime recognition and selectable async sessions; depends on VoxCore and AsyncAlgorithms.
- `VoxSpeechWhisperKit`: isolated local-model adapters; depends on VoxCore, VoxSpeech and WhisperKit.
- `VoxRefine`: refinement requests, responses, analysis values and prompt building; depends only on VoxCore.
- `VoxLLM`: Apple Intelligence/Azure providers and refinement services; depends on VoxCore, VoxRefine and AsyncAlgorithms. `LLMService` and `DefaultLLMService` are package-scoped implementation details; public consumers use providers or workflow APIs.
- `VoxWorkflow`: validated workflow definitions, layered async execution, DSL and provider presets; depends on the phase-2 SDK modules.
- `VoxWorkflowWhisperKit`: local WhisperKit workflow presets and model-loading-preserving source adapters; depends on VoxWorkflow and VoxSpeechWhisperKit.

SDK tests follow the tested module. Golden traces (a) and (c), their injected async probes
and both fixtures live in `Tests/GoldenTraceTests`; App routing (b) and Combine/Loki mapping remain host-owned.
`Examples/MinimalConsumer` links the workflow API and the four non-WhisperKit products on macOS/iOS; redline checks
build it and inspect its linked symbols/modules. R1–R4 cover all SDK sources, R5 also covers
tests and examples, and the typed logging fixtures compile for macOS and iOS Simulator.

# Runtime architecture notes

Last-Reviewed: 2026-09-24

Cross-layer runtime facts moved here from the former CLAUDE.md (repository rules live in
`AGENTS.md`; per-layer facts live in each `tech-context.md`). Build order of
`ServiceContainer` is in `VoxPocket/tech-context.md`.

- **Swift tools**: 6.2 · **Platforms**: iOS 26+, macOS 26+ · external SPM dependencies:
  `swift-async-algorithms` (LLMKit), `WhisperKit` (TranscriptionKit).

### Key Patterns

- **Protocol-driven DI**: Core contracts are protocols (`RecordingUseCase`, `EditingUseCase`, `LLMService`, `TextHistoryManaging`). Default implementations prefixed with `Default`. Test doubles prefixed with `Fake` or `Mock`.
- **Concurrency**: Hybrid Combine + async/await. Thread-safe state via `Mutex<State>` from the `Synchronization` framework. `@unchecked Sendable` used for Combine compatibility. `@MainActor` on view models and UI code.
- **Streaming**: `AsyncThrowingStream` for transcription and LLM refinement events.
- **State management**: `ViewState` protocols define the view-model contract. `@Published` properties drive SwiftUI updates.
- **ProxySessionUseCase**: Wraps any `SessionUseCase` and allows swapping the backing implementation at runtime without changing call sites.

### Key Flows

- **Quick Recording** (macOS): `AppDelegate` hotkey (Fn) → `ServiceContainer.tryStartRecording()` → `WindowManager` shows floating panel → `QuickRecordingViewModel` orchestrates the full pipeline: `startRecording()` → `stopRecording()` → waits for final transcription (15s timeout) → `refineStreaming()` → `clipboardService.copy()` + `simulatePaste()` → `onComplete` callback → window hides.
- **Full Editor**: `EditorViewModel` drives recording with 2.5s silence auto-stop. Refinement streamed via `RefinementUseCase.refineStreaming()`.
- **Transcription**: `DefaultTranscriptionUseCase` bridges the `TranscriptionCoordinator` to two publishers — `liveTextPublisher` (real-time, may change) and `finalResultPublisher` (stable, emits once after stop).
- **Refinement**: `RefinementUseCase` → `LLMService` → `AppleIntelligenceProvider` → streaming `RefinementEvent` results.
- **Text History**: Patch-based undo/redo via `TextHistoryManaging` with `Checkpoint` snapshots.

### Transcriber Providers

Configured in `LLMAppConfig.defaultTranscriberProvider`:

| Provider | Description |
|---|---|
| `.appleSpeech` | Apple Speech Recognition only |
| `.localWhisperKit` | WhisperKit local model, falls back to AppleSpeech while loading |
| `.hybridWhisper` | AppleSpeech real-time preview + Azure Whisper for final quality |
| `.hybridLocalWhisper` | AppleSpeech real-time preview + local WhisperKit for final quality |

For hybrid providers, `LLMTranscriptionMerger` uses an LLM call to reconcile the two transcripts.

### Environment Variables

Azure model credentials also support a user-approved runtime-only `config.private.json` in the app sandbox. Read `docs/architecture/private-model-config.md` before changing this path; only the empty template belongs in Git, and private files must stay out of app bundles.

| Variable | Purpose |
|---|---|
| `whisperkey` | Azure Whisper API key |
| `kimikey` / `AZURE_API_KEY` | Azure AI Foundry API key |
| `LOKI_ENDPOINT` | Loki push URL (debug defaults to `http://localhost:3100/loki/api/v1/push`) |
| `LOKI_TOKEN` | Loki Bearer token for Grafana Cloud |
| `CLAUDE_API_KEY` / `ANTHROPIC_API_KEY` | Claude Vision API key for `VoxAgentEval` UI evaluation |

### Platform-Specific Code

macOS services in `PlatformAdapters`: `MacOSClipboardService`, `MacOSAccessibilityService`, `MacOSGlobalHotkeyService`, `MacOSClaudeInboxService`. Cross-platform protocols exist for each. `WindowManager` manages floating `NSPanel` windows (`FullPanel`, `QuickRecording`).

### Telemetry

`LokiTelemetryService` (from the standalone `LokiKit` package) ships events to Grafana Loki. Offline events are persisted to `~/Library/Application Support/VoxPocket/telemetry/pending/` and retried on next `flush()`. `ServiceContainer.endRecording()` triggers a flush. Local stack: see `docker/telemetry/README.md` (`docker compose up -d`) → Grafana at `http://localhost:3010` (admin / telemetry), Loki at `http://localhost:3100`.

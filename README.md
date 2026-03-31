# VoxPocket

A macOS/iOS voice recording and transcription app built with SwiftUI. Records audio, transcribes speech using Apple Speech and/or WhisperKit, and refines text using Apple Intelligence on-device LLM.

## Features

- **Real-time transcription** via Apple Speech Framework
- **High-quality offline transcription** via WhisperKit (Core ML, on-device)
- **Text refinement** via Apple Intelligence (on-device LLM, iOS/macOS 26+)
- **Quick Recording** — global hotkey to record and inject text directly into any app
- **Hybrid mode** — Apple Speech drives live UI + auto-stop, WhisperKit improves final result
- **Auto-stop** after 2.5s of silence
- **Patch-based undo/redo** for transcription history

## Requirements

- macOS 26+ / iOS 26+
- Xcode 26+
- Apple Intelligence enabled on device (for text refinement)

## Getting Started

```bash
git clone https://github.com/your-org/VoxPocket.git
cd VoxPocket
open VoxPocket/VoxPocket.xcodeproj
```

### Configuration

All secrets are injected via **Xcode Scheme environment variables** — nothing is hardcoded.

| Variable | Description |
|---|---|
| `AZURE_FOUNDRY_ENDPOINT` | Azure AI Foundry endpoint URL (optional, for cloud LLM) |
| `AZURE_FOUNDRY_MODEL` | Model identifier, default: `gpt-4o` |
| `AZURE_API_KEY` | Azure API key (optional) |
| `whisperkey` | Azure OpenAI Whisper API key (optional) |

Without any variables configured, the app runs fully offline using Apple Speech + WhisperKit + Apple Intelligence.

### Bundle Identifier

The bundle identifier is set to `com.tianpli.VoxPocket` by default. Change it to your own in:
- Xcode project settings → Signing & Capabilities
- `VoxPocketWidget/` target settings
- `VoxPocket.entitlements` (iCloud container ID)

## Architecture

Four Swift Package Manager packages in a strict layered hierarchy:

```
VoxPresentation   (SwiftUI views, ViewModels)
      ↓
VoxApplication    (use cases / business logic)
      ↓
VoxInfrastructure (TranscriptionKit, LLMKit, Persistence, PlatformAdapters)
      ↓
VoxDomain         (pure domain models, no external deps)
```

See [`docs/architecture/`](docs/architecture/) for detailed diagrams.

## Key Design Patterns

- **Protocol-driven DI** — core contracts are protocols; implementations prefixed `Default`, test doubles prefixed `Fake`/`Mock`
- **Hybrid concurrency** — Combine for reactive bindings + async/await for imperative flows
- **Patch-based text history** — undo/redo via `Patch`/`Checkpoint` in VoxDomain
- **Streaming LLM** — `AsyncThrowingStream` for real-time refinement output

## Building Packages Individually

```bash
swift build --package-path Packages/VoxDomain
swift build --package-path Packages/VoxInfrastructure
swift build --package-path Packages/VoxApplication
swift build --package-path Packages/VoxPresentation

# Run tests
swift test --package-path Packages/VoxDomain
swift test --package-path Packages/VoxPresentation
```

## Test Automation

The repository now uses manifest-driven test automation with separate PR and nightly workflows.

Key pieces:

- Test manifests: `tests/manifests/*.tests.manifest.json`
- Test executor entrypoints: `scripts/test-executor/run_pr.sh` and `scripts/test-executor/run_nightly.sh`
- GitHub Actions workflows: `tests-pr` and `tests-nightly`
- Performance runner: `scripts/perf/run_perf_suite.sh`

Local dry-run commands:

```bash
# Resolve the PR performance command and thresholds without running xcodebuild
zsh scripts/perf/run_perf_suite.sh smoke --dry-run

# Resolve the full performance command and thresholds without running xcodebuild
zsh scripts/perf/run_perf_suite.sh full --dry-run
```

Performance runs read metrics from `artifacts/performance/raw-metrics.json` and emit summary files under `artifacts/performance/`.

## Local Code Review

This repo uses a local AI review gate on commits and merges. See [`docs/LOCAL_REVIEW.md`](docs/LOCAL_REVIEW.md).

## License

MIT — see [LICENSE](LICENSE).

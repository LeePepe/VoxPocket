# VoxPocket

Last-Reviewed: 2026-09-12

A macOS/iOS voice recording and transcription app built with SwiftUI. Supports Apple Speech, local WhisperKit and configured Azure transcription, with on-device or configured cloud text refinement.

## Features

- **Real-time transcription** via Apple Speech Framework
- **High-quality offline transcription** via WhisperKit (Core ML, on-device)
- **Configured cloud transcription** via Azure, including hybrid recognition paths
- **Text refinement** via Apple Intelligence (on-device LLM, iOS/macOS 26+)
- **Quick Recording** — global hotkey to record and inject text directly into any app
- **Hybrid mode** — Apple Speech drives live UI + auto-stop, WhisperKit improves final result
- **Auto-stop** after 2.5s of silence
- **Patch-based undo/redo** for transcription history

## Requirements

- macOS 26+ / iOS 26+
- Xcode 26+
- Apple Intelligence enabled on device when using on-device text refinement

## Getting Started

```bash
git clone https://github.com/LeePepe/VoxPocket.git
cd VoxPocket
open VoxPocket/VoxPocket.xcodeproj
```

The project uses sibling external packages, including LokiKit; use the package manifests and `VoxPocket/project.yml` as the dependency source of truth. CI checks out the required sibling repositories and regenerates the Xcode project.

User-facing builds are delivered through TestFlight. See [AGENTS.md](AGENTS.md) for the build/install boundary and [the release workflow](.github/workflows/testflight.yml) for current dispatch options. Agents do not replace the installed App with a local archive.

### Configuration

Azure configuration can come from the protected App-sandbox `config.private.json`; environment overrides remain supported. Follow [private model configuration](docs/architecture/private-model-config.md) and the credential-free `config.example.json`. Never commit private configuration or bundle it in the App.

Select a provider supported by the device and its configuration. Apple Speech availability does not by itself guarantee an on-device route, and cloud providers require valid configured credentials; do not assume an unconfigured installation is fully offline.

### Bundle Identifier

The App bundle identifier is `com.leepepe.voxpocket`, and its widget uses `com.leepepe.voxpocket.widget`. Their source of truth is `VoxPocket/project.yml`; signing profiles and entitlements must stay aligned with any deliberate identifier change.

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

The repository retains manifest-driven test executor scripts. Required CI is defined by the current workflows and branch ruleset, not by the presence of a manifest.

Key pieces:

- Test manifests: `tests/manifests/*.tests.manifest.json`
- Test executor entrypoints: `scripts/test-executor/run_pr.sh` and `scripts/test-executor/run_nightly.sh`
- Required build/test workflow: `.github/workflows/ci.yml`
- Required AI review: `.github/workflows/codex-review-target.yml`
- Performance runner: `scripts/perf/run_perf_suite.sh`

Local dry-run commands:

```bash
# Resolve the PR performance command and thresholds without running xcodebuild
zsh scripts/perf/run_perf_suite.sh smoke --dry-run

# Resolve the full performance command and thresholds without running xcodebuild
zsh scripts/perf/run_perf_suite.sh full --dry-run
```

Performance runs read metrics from `artifacts/performance/raw-metrics.json` and emit summary files under `artifacts/performance/`.

## Harness Engineering

This repository adopts a phased harness-engineering rollout focused on repo readability and feedback loops for agentic development.

Key entry points:

- Baseline metrics contract: `docs/harness/metrics-baseline.md`
- Baseline collector: `scripts/docs/collect_harness_baseline.sh`
- Records map (system of record): `docs/records/index.md`
- Docs checks: `scripts/docs/lint_docs_map.sh` and `scripts/docs/lint_docs_freshness.sh`
- Adoption checklist (Phase 0-1): `docs/harness/adoption-checklist-phase0-1.md`

Common local commands:

```bash
# Collect baseline metrics without writing files
zsh scripts/docs/collect_harness_baseline.sh \
  --window-start 2026-03-01 \
  --window-end 2026-03-31 \
  --dry-run

# Validate docs map and freshness constraints
zsh scripts/docs/lint_docs_map.sh
zsh scripts/docs/lint_docs_freshness.sh
```

## Local Code Review

This repo uses a local AI review gate on commits and merges. See [`docs/LOCAL_REVIEW.md`](docs/LOCAL_REVIEW.md).

## License

MIT — see [LICENSE](LICENSE).

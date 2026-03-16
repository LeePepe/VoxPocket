# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoxPocket is a macOS/iOS voice recording and transcription app built with SwiftUI. It captures audio, transcribes speech (default locale: `zh-Hans`), and refines text using Apple Intelligence LLM. The codebase uses Chinese comments throughout.

## Build & Test Commands

```bash
# Build the full Xcode project (macOS)
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build

# Build individual packages
swift build --package-path Packages/VoxDomain
swift build --package-path Packages/VoxInfrastructure
swift build --package-path Packages/VoxApplication
swift build --package-path Packages/VoxPresentation

# Run all tests for a package
swift test --package-path Packages/VoxDomain
swift test --package-path Packages/VoxPresentation

# Run a single test
swift test --package-path Packages/VoxPresentation --filter EditorAutoStopTests
```

## Architecture

Four SPM packages in a strict layered dependency hierarchy:

```
VoxPresentation  (SwiftUI views, view models)
       ↓
VoxApplication   (use cases / business logic)
       ↓
VoxInfrastructure (services: TranscriptionKit, LLMKit, Persistence, Observability, PlatformAdapters, Preferences)
       ↓
VoxDomain        (pure domain models: CoreModels, TextHistory — no external deps)
```

The app entry point is `VoxPocket/VoxPocket/` with `ServiceContainer` as the singleton DI container.

- **Swift Tools Version**: 6.2 | **Platforms**: iOS 26+, macOS 26+
- **External dependency**: `swift-async-algorithms` (used in LLMKit)

## Key Patterns

- **Protocol-driven DI**: Core contracts are protocols (`RecordingUseCase`, `EditingUseCase`, `LLMService`, `TextHistoryManaging`). Default implementations prefixed with `Default` (e.g., `DefaultRecordingUseCase`). Test doubles prefixed with `Fake` or `Mock`.
- **Concurrency**: Hybrid Combine + async/await. Thread-safe state via `Mutex<State>` from the `Synchronization` framework. `@unchecked Sendable` used for Combine compatibility. `@MainActor` on view models and UI code.
- **Streaming**: `AsyncThrowingStream` for transcription and LLM refinement events.
- **State management**: ViewState protocols define the view-model contract. `@Published` properties drive SwiftUI updates.

## Key Flows

- **Recording**: `EditorViewModel` → `RecordingUseCase` → `AppleSpeechTranscriber` (audio capture + speech recognition). Auto-stop triggers after 2.5s silence.
- **Refinement**: `RefinementUseCase` → `LLMService` (`AppleIntelligenceProvider`) → streaming `RefinementEvent` results.
- **Text History**: Patch-based undo/redo via `TextHistoryManaging` with `Checkpoint` snapshots.

## Platform-Specific Code

macOS services in PlatformAdapters: `MacOSClipboardService`, `MacOSAccessibilityService`, `MacOSGlobalHotkeyService`. Cross-platform protocols exist for each.

## Auto-Commit Workflow

After every logical change, Claude MUST:
1. Build the affected package with `swift build` to verify no errors
2. If build passes, immediately commit to `main` with a conventional commit message — no need to ask for permission
3. Use `git add <specific files>` (never `git add -A`) and commit directly to `main`

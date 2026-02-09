# AGENTS.md

## Project overview

VoxPocket is a macOS/iOS voice transcription app (SwiftUI). It records audio, transcribes speech via Apple Speech framework (default locale: `zh-Hans`), and refines text with Apple Intelligence. Chinese comments are used throughout the codebase.

## Architecture

Four SPM packages in a strict layered hierarchy — each layer only depends on layers below it:

```
VoxPresentation  →  VoxApplication  →  VoxInfrastructure  →  VoxDomain
(UI/ViewModels)     (UseCases)         (Services)            (Models)
```

- **VoxDomain**: Pure domain models (`CoreModels`, `TextHistory`), no external deps
- **VoxInfrastructure**: `TranscriptionKit`, `LLMKit`, `Persistence`, `Observability`, `PlatformAdapters`, `Preferences`
- **VoxApplication**: `UseCases` — business logic bridging domain and infrastructure
- **VoxPresentation**: `UIShared`, `PlatformUI` — SwiftUI views and view models

App entry point: `VoxPocket/VoxPocket/` with `ServiceContainer` as singleton DI container.

Swift Tools Version 6.2 | Platforms: iOS 26+, macOS 26+

## Setup commands

```bash
# Build the Xcode project (macOS)
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build

# Build a single package
swift build --package-path Packages/VoxDomain

# Run all tests for a package
swift test --package-path Packages/VoxPresentation

# Run a specific test class
swift test --package-path Packages/VoxPresentation --filter EditorAutoStopTests
```

## Code style

- Protocol-driven DI: contracts are protocols (`RecordingUseCase`, `LLMService`, `TextHistoryManaging`)
- Default implementations prefixed with `Default` (e.g. `DefaultRecordingUseCase`)
- Test doubles prefixed with `Fake` or `Mock`
- Concurrency: hybrid Combine + async/await; thread-safe state via `Mutex<State>` from `Synchronization`; `@MainActor` on view models and UI code
- ViewState protocols define the view-model contract; `@Published` properties drive SwiftUI

## Testing instructions

- Tests use XCTest with async/await support
- Test targets exist per package: `CoreModelsTests`, `TextHistoryTests`, `TranscriptionKitTests`, `LLMKitTests`, `PersistenceTests`, `UseCasesTests`, `UISharedTests`
- Use `Fake`/`Mock` implementations for isolation — no third-party mocking frameworks
- Run the relevant package tests before submitting changes:
  ```bash
  swift test --package-path Packages/VoxPresentation
  swift test --package-path Packages/VoxApplication
  ```

## PR instructions

- Keep PR titles concise, using conventional prefixes: `feat:`, `fix:`, `docs:`, `refactor:`
- Ensure all tests pass in affected packages before opening a PR
- Do not add dependencies to `VoxDomain` — it must remain pure Swift with zero external deps

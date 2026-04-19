# Implementation Plan: Extract Telemetry Kit into Standalone SPM Package

## Status: APPROVED

## Acceptance Criteria
- [ ] New standalone SPM package `LokiKit` exists at `/Users/tianpli/Development/LokiKit/` and builds successfully with `swift build`
- [ ] `LokiKit` has no VoxPocket-specific coupling (no hardcoded "VoxPocket" strings, no app-specific event names)
- [ ] `LokiKit` exposes a clean public API: `Logger`, `LogLevel`, `PrintLogger`, `TelemetryService`, `TelemetryEvent`, `LokiTelemetryService`, `NoopTelemetryService`
- [ ] `VoxInfrastructure` is updated to depend on `LokiKit` via local path reference and no longer contains the `Observability` target sources
- [ ] `swift build --package-path Packages/VoxInfrastructure` in VoxPocket succeeds
- [ ] `swift build --package-path Packages/VoxApplication` in VoxPocket succeeds
- [ ] Tests from `ObservabilityTests` are migrated to `LokiKit` and pass with `swift test`

## Scope

Extract the `Observability` module from `VoxInfrastructure` into a standalone, reusable SPM package named `LokiKit`. Update VoxPocket to depend on it via SPM local path.

## Key Findings

- `Observability` module: 7 Swift source files, ~600 lines
- Listed dependency on `CoreModels` (VoxDomain) is **unused** — no import statement in any Observability source file. Safe to drop entirely from LokiKit.
- VoxPocket-specific coupling to remove from LokiKit:
  1. `LokiTelemetryService.swift` line 48: hardcoded `"VoxPocket"` as default app label → remove default, require caller to pass `appLabels`
  2. `TelemetryQueue.swift` line 27: hardcoded `"VoxPocket/telemetry/pending"` as default store path → change to `"telemetry/pending"`
  3. `TelemetryService.swift`: `TelemetryEventName` enum contains VoxPocket-specific event names → move to VoxInfrastructure as `VoxPocketTelemetryEventNames.swift`
- `TelemetryEventName` is used in: TranscriptionKit (WhisperKitTranscriber), VoxApplication (4 use case files), VoxPresentation (QuickRecordingViewModel), ServiceContainer → keep in VoxInfrastructure as new file

## Architecture

```
LokiKit (new standalone repo at ~/Development/LokiKit)
  Sources/LokiKit/
    Logger.swift           (protocol + extensions)
    LogLevel.swift         (enum)
    PrintLogger.swift      (concrete print impl)
    TelemetryService.swift (protocol + NoopTelemetryService; TelemetryEvent struct; NO TelemetryEventName)
    LokiTelemetryService.swift (no hardcoded "VoxPocket" default)
    LokiShipper.swift      (HTTP push client)
    TelemetryQueue.swift   (offline queue; no "VoxPocket" in default path)
  Tests/LokiKitTests/
    TelemetryQueueTests.swift
    PrintLoggerTimestampTests.swift

VoxPocket/Packages/VoxInfrastructure/
  Package.swift: add LokiKit path dep; replace Observability target with LokiKit product
  Sources/Observability/: DELETE all 7 files
  Sources/TranscriptionKit/VoxPocketTelemetryEventNames.swift: NEW — TelemetryEventName enum
  Tests/ObservabilityTests/: DELETE (migrated to LokiKit)
```

## Files to Create (LokiKit)

| File | Operation |
|------|-----------|
| `/Users/tianpli/Development/LokiKit/Package.swift` | Create — standalone SPM, platforms iOS 26+/macOS 26+, no external deps |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/Logger.swift` | Create — copied, unchanged |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/LogLevel.swift` | Create — copied, unchanged |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/PrintLogger.swift` | Create — copied, unchanged |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/TelemetryService.swift` | Create — remove TelemetryEventName; keep TelemetryEvent struct here |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/LokiTelemetryService.swift` | Create — remove hardcoded "VoxPocket" default |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/LokiShipper.swift` | Create — copied, unchanged |
| `/Users/tianpli/Development/LokiKit/Sources/LokiKit/TelemetryQueue.swift` | Create — change default path to "telemetry/pending" |
| `/Users/tianpli/Development/LokiKit/Tests/LokiKitTests/TelemetryQueueTests.swift` | Create — migrated, update import |
| `/Users/tianpli/Development/LokiKit/Tests/LokiKitTests/PrintLoggerTimestampTests.swift` | Create — migrated, update import |
| `/Users/tianpli/Development/LokiKit/.gitignore` | Create — standard Swift gitignore |
| `/Users/tianpli/Development/LokiKit/README.md` | Create — brief docs |

## Files to Create in VoxPocket

| File | Operation |
|------|-----------|
| `Packages/VoxInfrastructure/Sources/TranscriptionKit/VoxPocketTelemetryEventNames.swift` | Create — TelemetryEventName enum moved here |

## Files to Modify in VoxPocket

| File | Change |
|------|--------|
| `Packages/VoxInfrastructure/Package.swift` | Add LokiKit path dep; remove Observability target; add LokiKit product to TranscriptionKit, LLMKit, PlatformAdapters |
| `Packages/VoxInfrastructure/Sources/TranscriptionKit/*.swift` (7 files) | `import Observability` → `import LokiKit` |
| `Packages/VoxInfrastructure/Sources/LLMKit/**/*.swift` (4 files) | `import Observability` → `import LokiKit` |
| `Packages/VoxInfrastructure/Sources/PlatformAdapters/*.swift` (4 files) | `import Observability` → `import LokiKit` |
| `Packages/VoxApplication/Package.swift` | Add `.package(path: "../../LokiKit")`; replace Observability dep with LokiKit |
| `Packages/VoxApplication/Sources/UseCases/*.swift` (4 files) | `import Observability` → `import LokiKit` |
| `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift` | `import Observability` → `import LokiKit` (if direct import exists) |
| `VoxPocket/VoxPocket/ServiceContainer.swift` | Update LokiTelemetryService init to pass `appLabels: ["app": "VoxPocket"]` explicitly |

## Files to Delete in VoxPocket

| File | Reason |
|------|--------|
| `Packages/VoxInfrastructure/Sources/Observability/` (all 7 files) | Replaced by LokiKit |
| `Packages/VoxInfrastructure/Tests/ObservabilityTests/` (2 files) | Migrated to LokiKit |

## Execution Steps

1. Create LokiKit directory structure and Package.swift
2. Copy and adapt 7 source files (removing VoxPocket coupling)
3. Migrate 2 test files
4. Create VoxPocketTelemetryEventNames.swift in TranscriptionKit
5. Update VoxInfrastructure/Package.swift
6. Update all `import Observability` → `import LokiKit` across 15 files
7. Update VoxApplication/Package.swift
8. Check VoxPresentation for direct Observability imports
9. Update ServiceContainer.swift appLabels
10. Delete old Observability files
11. Verify: `swift build` for LokiKit, VoxInfrastructure, VoxApplication

## Risks
- Missing any import rename will cause build error (caught by verification step)
- VoxPresentation does not directly import Observability in Package.swift but QuickRecordingViewModel uses TelemetryEventName — must add LokiKit dep to VoxPresentation if it imports LokiKit directly, OR it gets TelemetryEventName via TranscriptionKit/UseCases transitively

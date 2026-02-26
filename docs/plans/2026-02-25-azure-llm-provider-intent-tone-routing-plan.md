# Azure LLM Provider + Intent/Tone Routing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an Azure Foundry remote LLM provider and allow intent/tone analysis to be configured independently to use local (Apple Intelligence) or remote provider.

**Architecture:** Extend `LLMKit` with a new `AzureFoundryProvider` implementing `LLMProvider` for completion + analysis. Keep `DefaultLLMService` as the workflow orchestrator and expose explicit analysis-routing configuration options for intent/tone. Wire startup configuration in `ServiceContainer` from environment variables so the app can run without UI changes.

**Tech Stack:** Swift 6.2, URLSession, XCTest, existing `LLMKit` provider abstractions.

### Task 1: Add provider-level tests first (TDD)

**Files:**
- Modify: `Packages/VoxInfrastructure/Tests/LLMKitTests/LLMKitTests.swift`

**Step 1: Write failing tests for provider parsing + routing config behavior**
- Add unit tests for:
  - `LLMProviderType` supports Azure Foundry type.
  - `DefaultLLMService` analysis override option keys accept local/remote split for `intent` and `tone`.

**Step 2: Run test to verify it fails**
- Run: `swift test --package-path Packages/VoxInfrastructure --filter LLMKitTests`
- Expected: fail because Azure type and parsing behavior are missing.

### Task 2: Implement Azure provider and provider routing support

**Files:**
- Modify: `Packages/VoxInfrastructure/Sources/LLMKit/Protocols/LLMProvider.swift`
- Create: `Packages/VoxInfrastructure/Sources/LLMKit/Providers/AzureFoundryProvider.swift`
- Modify: `Packages/VoxInfrastructure/Sources/LLMKit/Services/DefaultLLMService.swift`

**Step 1: Add Azure provider type**
- Extend `LLMProviderType` with `azureFoundry` raw value.

**Step 2: Implement `AzureFoundryProvider`**
- Use Azure AI Foundry `/chat/completions` style REST call via `URLSession`.
- Parse response text for completion.
- Implement `analyze(_:steps:)` by structured JSON prompting compatible with current `IntentAnalysis` and `ToneAnalysis`.
- Return safe defaults on parse failure where needed.

**Step 3: Register provider in `DefaultLLMService`**
- Add init path to include Azure provider when config is present.
- Keep existing Apple provider behavior unchanged.

### Task 3: Wire app-level config for current workflow

**Files:**
- Modify: `VoxPocket/VoxPocket/ServiceContainer.swift`

**Step 1: Read runtime configuration**
- Read env vars for:
  - `VOX_LLM_PROVIDER`
  - `VOX_AZURE_FOUNDRY_ENDPOINT`
  - `VOX_AZURE_FOUNDRY_API_KEY`
  - `VOX_AZURE_FOUNDRY_MODEL`
  - `VOX_ANALYSIS_INTENT_PROVIDER`
  - `VOX_ANALYSIS_TONE_PROVIDER`

**Step 2: Configure llm service**
- Build `LLMProviderConfig` with analysis override options:
  - `analysis.intent.provider`
  - `analysis.tone.provider`
- Apply with `setProvider` during startup.

### Task 4: Verify and regressions

**Files:**
- Modify (if needed): tests touched above

**Step 1: Run package tests**
- Run: `swift test --package-path Packages/VoxInfrastructure --filter LLMKitTests`
- Expected: pass.

**Step 2: Run targeted app compile check (optional if env allows)**
- Run: `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`
- Expected: compile success.

# Implementation Plan: Azure Foundry Transcriber Model Enum

## Status: APPROVED (v3)

## Scope
Add `AzureFoundryTranscriberModel` enum to switch between Azure transcription deployments.
Default to `gpt-4o-transcribe`. Add `gpt-4o-mini-transcribe` and `gpt-4o-transcribe`.
`WhisperEngine`, `AzureWhisperTranscriber`, `HybridWhisperTranscriber` — NO changes needed.

## Architecture Decision

`AzureFoundryTranscriberModel` goes in **`VoxInfrastructure/TranscriptionKit`** (new file).

Rationale:
- `deploymentName` and `apiVersion` are knowledge about the Azure OpenAI Audio API capabilities — Infrastructure concerns
- App layer (`ServiceContainer`) imports it from Infrastructure and uses it to build URL → passes URL down via `AzureWhisperConfig`
- Infrastructure layer (`WhisperEngine`) never sees the enum, only the `AzureWhisperConfig.endpoint: URL`
- Dependency direction: App → Infrastructure ✓ (no reverse dependency)

## Files to Change

| File | Operation | Notes |
|------|-----------|-------|
| `Packages/VoxInfrastructure/Sources/TranscriptionKit/AzureFoundryTranscriberModel.swift` | Create | New enum in Infrastructure layer |
| `VoxPocket/VoxPocket/LLMAppConfig.swift` | Modify | Add `defaultAzureFoundryTranscriberModel` static property only |
| `VoxPocket/VoxPocket/ServiceContainer.swift` | Modify | Replace hardcoded endpoint in `makeAzureWhisperConfig()` |

---

## Step 1: Create `AzureFoundryTranscriberModel.swift` in TranscriptionKit

**Path**: `Packages/VoxInfrastructure/Sources/TranscriptionKit/AzureFoundryTranscriberModel.swift`

```swift
/// Azure Foundry 转录模型选择
///
/// 每个 case 对应一个 Azure OpenAI Audio Transcriptions deployment。
/// API request body（multipart form-data）格式对所有 case 完全相同，
/// 差异只体现在 endpoint URL 的 deploymentName 和 apiVersion 上。
public enum AzureFoundryTranscriberModel: Sendable {
    /// 经典 Whisper 模型（稳定，延迟较低）
    case whisper
    /// GPT-4o Transcribe（高精度，支持更多语言，含中文）
    case gpt4oTranscribe
    /// GPT-4o Mini Transcribe（低成本，速度更快）
    case gpt4oMiniTranscribe

    /// Azure deployment name，用于构造 URL 路径段
    public var deploymentName: String {
        switch self {
        case .whisper:              return "whisper"
        case .gpt4oTranscribe:     return "gpt-4o-transcribe"
        case .gpt4oMiniTranscribe: return "gpt-4o-mini-transcribe"
        }
    }

    /// Azure Audio API 版本
    /// gpt4oTranscribe 和 gpt4oMiniTranscribe 共用 2024-10-21（有意为之，两者同版本）
    public var apiVersion: String {
        switch self {
        case .whisper:              return "2024-06-01"
        case .gpt4oTranscribe:     return "2024-10-21"
        case .gpt4oMiniTranscribe: return "2024-10-21"
        }
    }
}
```

---

## Step 2: `LLMAppConfig.swift` — Add one static property

Add inside `LLMAppConfig` enum, after `defaultTranscriberProvider`:

```swift
/// 默认 Azure Foundry 转录模型
///
/// 切换此值即可全局切换 Azure 转录 deployment，无需修改任何基础设施代码。
/// 仅在 `defaultTranscriberProvider` 为 `.azureWhisper` 或 `.hybridWhisper` 时生效。
static let defaultAzureFoundryTranscriberModel: AzureFoundryTranscriberModel = .gpt4oTranscribe
```

No `azureWhisperBaseURL` static property — base URL is read inside `makeAzureWhisperConfig()` directly (avoids Swift 6 concurrency concerns with static lazy init).

---

## Step 3: `ServiceContainer.swift` — Replace `makeAzureWhisperConfig()`

**Old** (lines 257–267):
```swift
private static func makeAzureWhisperConfig() -> AzureWhisperConfig? {
    let env = ProcessInfo.processInfo.environment
    guard let apiKey = env["whisperkey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !apiKey.isEmpty else {
        return nil
    }
    // audio/transcriptions 保留原始语言（如中文）
    // audio/translations 会强制将所有音频翻译为英文
    let endpoint = URL(string: "https://tianp-mmd3pwyc-swedencentral.cognitiveservices.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-06-01")!
    return AzureWhisperConfig(endpoint: endpoint, apiKey: apiKey)
}
```

**New**:
```swift
private static func makeAzureWhisperConfig() -> AzureWhisperConfig? {
    let env = ProcessInfo.processInfo.environment
    guard let apiKey = env["whisperkey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !apiKey.isEmpty else {
        return nil
    }
    let model = LLMAppConfig.defaultAzureFoundryTranscriberModel
    // AZURE_WHISPER_BASE_URL must be a bare origin with no path
    // (e.g. "https://resource.cognitiveservices.azure.com")
    // Path is constructed below; any existing path in the base URL is intentionally discarded.
    let baseURLString = env["AZURE_WHISPER_BASE_URL"]
        ?? "https://tianp-mmd3pwyc-swedencentral.cognitiveservices.azure.com"
    // Guard against malformed env var — fall back to nil so caller can degrade gracefully
    guard var comps = URLComponents(string: baseURLString) else {
        return nil
    }
    // audio/transcriptions 保留原始语言（如中文）
    // audio/translations 会强制将所有音频翻译为英文
    comps.path = "/openai/deployments/\(model.deploymentName)/audio/transcriptions"
    comps.queryItems = [URLQueryItem(name: "api-version", value: model.apiVersion)]
    guard let endpoint = comps.url else { return nil }
    return AzureWhisperConfig(endpoint: endpoint, apiKey: apiKey)
}
```

Key changes:
- **URLComponents** instead of `appendingPathComponent` (avoids slash percent-encoding bug)
- Base URL read from `AZURE_WHISPER_BASE_URL` env var with fallback to existing hardcoded value
- Preserves existing comment about `transcriptions` vs `translations`
- No `static let` for base URL (avoids Swift 6 concurrency concerns)

---

## Execution Order

Note: `Package.swift` does NOT need to be modified — `TranscriptionKit` target uses automatic source discovery (no explicit `sources` parameter), so any new `.swift` file in `Sources/TranscriptionKit/` is compiled automatically.

1. Create `AzureFoundryTranscriberModel.swift` in TranscriptionKit
2. Modify `LLMAppConfig.swift` — add `defaultAzureFoundryTranscriberModel`
3. Modify `ServiceContainer.swift` — replace `makeAzureWhisperConfig()`
4. Build: `swift build --package-path Packages/VoxInfrastructure` then `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`

---

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `URLComponents(string:)` returns nil if base URL is malformed | LOW | fallback string is a known-valid URL; env var validated implicitly |
| `comps.url` is nil if path/query construction fails | VERY LOW | path is a simple string with no special chars; queryItems are valid |
| `gpt-4o-transcribe` deployment not created in Azure portal yet | MEDIUM | runtime: `makeAzureWhisperConfig()` returns valid config, but API returns 404; fallback to AppleSpeech via existing error handling |
| Deployment name differs from model name in user's Azure resource | BY DESIGN | `deploymentName` is a convention; users can fork the enum if needed |

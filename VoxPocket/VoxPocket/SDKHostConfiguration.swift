import Foundation
import VoxSpeech
import VoxCore
import VoxKitBridge

struct SDKHostConfiguration: Sendable {
    let storageLocations: VoxStorageLocations
    let logger: any VoxLogger
    let telemetry: any VoxTelemetry
    let credentials: any CredentialProvider

    static func storageLocations(fileManager: FileManager = .default) -> VoxStorageLocations {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var candidates = [caches.appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml", isDirectory: true)]
        #if os(macOS)
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml", isDirectory: true))
        #endif
        return VoxStorageLocations(
            temporaryAudio: support.appendingPathComponent("VoxPocket/TemporaryAudio", isDirectory: true),
            modelCache: caches.appendingPathComponent("VoxPocketWhisperKitHub", isDirectory: true),
            modelCacheCleanupCandidates: candidates)
    }

    @MainActor static func credentials(environment: [String: String]) -> EnvironmentCredentialProvider {
        var snapshot: [CredentialKey: Credential] = [:]
        let refinement = LLMAppConfig.refinementAPIKey(environment: environment).map(Credential.init(rawValue:))
        let values: [(CredentialKey, Credential?)] = [
            (.azureSpeechKey, LLMAppConfig.transcriptionConfig(environment: environment)?.apiKey),
            (.whisperKey, LLMAppConfig.transcriptionConfig(environment: environment)?.apiKey),
            (.azureFoundryAPIKey, refinement),
            (.llmAPIKey, refinement)
        ]
        for (key, value) in values {
            if let value, !value.isEmpty { snapshot[key] = value }
        }
        return EnvironmentCredentialProvider(snapshot: snapshot)
    }
}

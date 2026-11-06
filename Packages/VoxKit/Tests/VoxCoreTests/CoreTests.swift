import Foundation
import Testing
@testable import VoxCore

@Test func credentialIsRedactedEverywhere() {
    let credential = Credential(rawValue: "canary-secret")
    #expect(String(describing: credential) == "Credential(<redacted>)")
    #expect(String(reflecting: credential) == "Credential(<redacted>)")
    #expect("value=\(credential)" == "value=Credential(<redacted>)")
    #expect(Mirror(reflecting: credential).children.isEmpty)
    #expect(!String(describing: credential).contains("canary-secret"))
}

@Test func credentialValueSemantics() {
    let credential = Credential(rawValue: "canary-secret")
    #expect(credential == Credential(rawValue: "canary-secret"))
    #expect(credential != Credential(rawValue: "different-secret"))
    #expect(Set([credential, Credential(rawValue: "canary-secret")]).count == 1)
    #expect(!credential.isEmpty)
    #expect(Credential(rawValue: " \n\t").isEmpty)
}

@Test func coreContractsRecordSafeValues() {
    let field = VoxLogField.int("count", 2)
    #expect(field.value == .int(2))
    let event = VoxTelemetryEvent(name: "recording.completed", fields: [field])
    #expect(event.fields == [field])
    #expect(VoxLabel.appleSpeech == .provider("appleSpeech"))
}

@Test func storageAndNoops() {
    let locations = VoxStorageLocations(temporaryAudio: URL(string: "file:///tmp/audio")!, modelCache: URL(string: "file:///tmp/cache")!)
    #expect(locations.modelCache.lastPathComponent == "cache")
    #expect(NoopCredentialProvider().credential(for: .azureSpeechKey) == nil)
    NoopVoxLogger().info("safe")
    NoopVoxTelemetry().record(VoxTelemetryEvent(name: "safe"))
}

@Test func kitErrorDescriptionsRemainStable() {
    let cases: [(VoxKitError, String)] = [
        (.microphoneAccessDenied, "麦克风访问被拒绝，请在系统设置中允许访问"),
        (.speechRecognitionUnavailable, "语音识别服务不可用"),
        (.speechRecognitionPermissionDenied, "语音识别权限被拒绝，请在系统设置中允许"),
        (.transcriptionFailed(reason: .reason("timeout")), "转录失败：timeout"),
        (.unsupportedLanguage(locale: .reason("en-US")), "不支持的语言：en-US"),
        (.llmProviderNotConfigured, "LLM 提供者未配置"),
        (.llmRequestFailed(reason: .reason("unavailable")), "LLM 请求失败：unavailable"),
        (.llmResponseInvalid, "LLM 响应无效"),
        (.llmInvalidAPIKey, "无效的 API Key"),
        (.llmQuotaExceeded, "API 配额已用尽"),
        (.llmOperationTimeout, "LLM 操作超时"),
        (.modelNotReady, "本地模型正在加载中，请稍候再试")
    ]
    for (error, expected) in cases { #expect(error.errorDescription == expected) }
}

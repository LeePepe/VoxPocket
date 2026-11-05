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

@Test func coreContractsRecordSafeValues() {
    let field = VoxLogField.int("count", 2)
    #expect(field.value == .int(2))
    let event = VoxTelemetryEvent(name: "recording.completed", fields: [field])
    #expect(event.fields == [field])
    #expect(VoxLabel.appleSpeech == .provider("appleSpeech"))
}

@Test func storageAndNoops() {
    let locations = VoxStorageLocations(temporaryAudio: URL(fileURLWithPath: "/tmp/audio"), modelCache: URL(fileURLWithPath: "/tmp/cache"))
    #expect(locations.modelCache.lastPathComponent == "cache")
    #expect(NoopCredentialProvider().credential(for: .azureSpeechKey) == nil)
    NoopVoxLogger().info("safe")
    NoopVoxTelemetry().record(VoxTelemetryEvent(name: "safe"))
}

@Test func kitErrorDescriptionsRemainStable() {
    #expect(VoxKitError.microphoneAccessDenied.errorDescription == "麦克风访问被拒绝，请在系统设置中允许访问")
    #expect(VoxKitError.speechRecognitionUnavailable.errorDescription == "语音识别服务不可用")
    #expect(VoxKitError.modelNotReady.errorDescription == "本地模型正在加载中，请稍候再试")
}

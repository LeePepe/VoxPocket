import Foundation

public protocol SpeechSessionSource: AnyObject, Sendable {
    var supportedLanguages: [Locale] { get }
    var providerKind: ASRProviderType { get }
    var isActive: Bool { get }
    func requestMicrophonePermission() async -> Bool
    func requestSpeechPermission() async -> Bool
    var hasMicrophonePermission: Bool { get }
    var hasSpeechPermission: Bool { get }
    func captureStates() -> AsyncStream<AudioCaptureState>
    func audioLevels() -> AsyncStream<Float>
    func startSession(language: Locale) async throws -> any SpeechSession
}

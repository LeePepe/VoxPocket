import VoxCore
import Combine
import Foundation
import TranscriptionKit

public protocol SpeechRecognitionService: AnyObject, Sendable {
    var providerType: ASRProviderType { get }
    var resultPublisher: AnyPublisher<TranscriptionResult, Error> { get }
    func startRecognition(language: Locale) async throws
    func stopRecognition() async
    func checkAvailability() async -> Bool
    func requestPermission() async -> Bool
    var supportedLanguages: [Locale] { get }
}

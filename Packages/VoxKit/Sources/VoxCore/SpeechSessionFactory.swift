import Foundation

public protocol SpeechSessionFactory: Sendable {
    func makeSource() async throws -> any SpeechSessionSource
}

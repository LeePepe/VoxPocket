import VoxCore
import Foundation

public protocol SpeechAvailabilityProviding: Sendable {
    var isSpeechAvailable: Bool { get }
}

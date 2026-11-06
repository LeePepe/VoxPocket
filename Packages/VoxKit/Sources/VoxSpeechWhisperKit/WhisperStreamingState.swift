import Foundation
import Synchronization
import VoxCore
#if canImport(WhisperKit)
import WhisperKit

final class WhisperStreamingState: Sendable {
    private struct State {
        var lastSize = 0
        var confirmedEnd: Float = 0
        var confirmedSegments: [TranscriptionSegment] = []
        var peakConfirmed = ""
    }
    private let state = Mutex(State())
    func secondsSinceLastDecode(sampleCount: Int) -> Float {
        state.withLock { Float(sampleCount - $0.lastSize) / Float(WhisperKit.sampleRate) }
    }
    func beginDecode(sampleCount: Int) -> Float {
        state.withLock { state in
            state.lastSize = sampleCount
            return state.confirmedEnd
        }
    }
    func receive(_ progress: TranscriptionProgress) -> String {
        state.withLock { state in
            Self.clean([state.peakConfirmed, progress.text.trimmingCharacters(in: .whitespacesAndNewlines)]
                .filter { !$0.isEmpty }.joined(separator: " "))
        }
    }
    func confirm(_ segments: [TranscriptionSegment]) -> String {
        state.withLock { state in
            if segments.count > 2 {
                let confirmed = Array(segments.prefix(segments.count - 2))
                if let last = confirmed.last, last.end > state.confirmedEnd {
                    state.confirmedEnd = last.end
                    state.confirmedSegments.append(contentsOf: confirmed)
                }
            }
            let text = state.confirmedSegments.map(\.text).joined(separator: " ")
            if text.count > state.peakConfirmed.count { state.peakConfirmed = text }
            return Self.clean(state.peakConfirmed)
        }
    }
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]+\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

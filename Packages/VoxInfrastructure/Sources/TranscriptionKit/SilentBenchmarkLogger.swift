import Foundation
import LokiKit

/// Production-side benchmark seam: benchmark logs are intentionally silent in
/// synthetic/test runs and when a benchmark logger is injected into the adapter.
enum SilentBenchmarkLogger {
    static func log(_ message: String, logger: Logger? = nil) {
        _ = message
        _ = logger
    }

    static func suppress(_ rawText: String) -> String {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

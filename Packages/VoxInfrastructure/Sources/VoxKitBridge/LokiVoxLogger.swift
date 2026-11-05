import LokiKit
import VoxCore

public struct LokiVoxLogger: VoxLogger, Sendable {
    private let logger: any Logger
    public init(logger: any Logger) { self.logger = logger }
    public func log(_ level: VoxLogLevel, _ message: StaticString, fields: [VoxLogField]) {
        let context = Dictionary(fields.map { (String(describing: $0.key), contextValue($0.value)) }, uniquingKeysWith: { _, latest in latest })
        let mapped: LogLevel
        switch level {
        case .debug: mapped = .debug
        case .info: mapped = .info
        case .warning: mapped = .warning
        case .error: mapped = .error
        }
        logger.log(mapped, String(describing: message), context: context)
    }
    private func contextValue(_ value: VoxLogValue) -> Any {
        switch value {
        case .int(let count): return count
        case .double(let number), .durationMs(let number): return number
        case .bool(let flag): return flag
        case .label(let label): return label.rawLabel
        }
    }
}

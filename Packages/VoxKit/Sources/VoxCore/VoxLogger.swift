public enum VoxLogLevel: String, Sendable { case debug, info, warning, error }

public enum VoxLabel: Sendable, Equatable {
    case provider(StaticString)
    case step(StaticString)
    case reason(StaticString)
    case source(StaticString)
    case custom(index: Int)

    public static let appleSpeech = Self.provider("appleSpeech")
    public static let azure = Self.provider("azure")
    public static let whisperKit = Self.provider("whisperKit")

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    public var text: String {
        switch self {
        case .provider(let value): return "provider:\(value)"
        case .step(let value): return "step:\(value)"
        case .reason(let value): return "reason:\(value)"
        case .source(let value): return "source:\(value)"
        case .custom(let index): return "custom:\(index)"
        }
    }
}

public enum VoxLogValue: Sendable, Equatable {
    case int(Int)
    case double(Double)
    case durationMs(Double)
    case bool(Bool)
    case label(VoxLabel)
}

public struct VoxLogField: Sendable, Equatable {
    public let key: StaticString
    public let value: VoxLogValue
    public init(_ key: StaticString, _ value: VoxLogValue) { self.key = key; self.value = value }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        String(describing: lhs.key) == String(describing: rhs.key) && lhs.value == rhs.value
    }
    public static func int(_ key: StaticString, _ value: Int) -> Self { Self(key, .int(value)) }
    public static func double(_ key: StaticString, _ value: Double) -> Self { Self(key, .double(value)) }
    public static func durationMs(_ key: StaticString, _ value: Double) -> Self { Self(key, .durationMs(value)) }
    public static func bool(_ key: StaticString, _ value: Bool) -> Self { Self(key, .bool(value)) }
    public static func label(_ key: StaticString, _ value: VoxLabel) -> Self { Self(key, .label(value)) }
}

public protocol VoxLogger: Sendable {
    func log(_ level: VoxLogLevel, _ message: StaticString, fields: [VoxLogField])
}

public extension VoxLogger {
    func debug(_ message: StaticString, fields: [VoxLogField] = []) { log(.debug, message, fields: fields) }
    func info(_ message: StaticString, fields: [VoxLogField] = []) { log(.info, message, fields: fields) }
    func warning(_ message: StaticString, fields: [VoxLogField] = []) { log(.warning, message, fields: fields) }
    func error(_ message: StaticString, fields: [VoxLogField] = []) { log(.error, message, fields: fields) }
}

public struct NoopVoxLogger: VoxLogger, Sendable {
    public init() {}
    public func log(_ level: VoxLogLevel, _ message: StaticString, fields: [VoxLogField]) {}
}

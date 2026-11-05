public struct VoxTelemetryEvent: Sendable, Equatable {
    public let name: StaticString
    public let fields: [VoxLogField]
    public init(name: StaticString, fields: [VoxLogField] = []) { self.name = name; self.fields = fields }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        String(describing: lhs.name) == String(describing: rhs.name) && lhs.fields == rhs.fields
    }
}

public protocol VoxTelemetry: Sendable {
    func record(_ event: VoxTelemetryEvent)
}

public struct NoopVoxTelemetry: VoxTelemetry, Sendable {
    public init() {}
    public func record(_ event: VoxTelemetryEvent) {}
}

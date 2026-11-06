import Foundation
import Synchronization

public final class CanaryLogger: VoxLogger, Sendable {
    private let state = Mutex(State())
    private struct State: Sendable {
        var messages: [String] = []
        var fields: [[VoxLogField]] = []
    }

    public init() {}
    public func log(_ level: VoxLogLevel, _ message: StaticString, fields: [VoxLogField]) {
        state.withLock { state in
            state.messages.append(String(describing: message))
            state.fields.append(fields)
        }
    }
    public var recordedMessages: [String] { state.withLock { $0.messages } }
    public var recordedFields: [[VoxLogField]] { state.withLock { $0.fields } }

    public func assertNoCanaryLeak(canaryStrings: [String], error: Error? = nil) -> Bool {
        let values = recordedMessages + recordedFields.flatMap { fields in fields.flatMap(fieldValues) } + errorValues(error)
        return !canaryStrings.contains { canary in values.contains { $0.contains(canary) } }
    }

    private func fieldValues(_ field: VoxLogField) -> [String] {
        [String(describing: field.key), field.value.text]
    }

    private func errorValues(_ error: Error?) -> [String] {
        guard let error else { return [] }
        var values = [error.localizedDescription, String(describing: error)]
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            values.append(description)
        }
        return values
    }
}

public final class CanaryTelemetry: VoxTelemetry, Sendable {
    private let state = Mutex([VoxTelemetryEvent]())
    public init() {}
    public func record(_ event: VoxTelemetryEvent) { state.withLock { $0.append(event) } }
    public var recordedEvents: [VoxTelemetryEvent] { state.withLock { $0 } }

    public func assertNoCanaryLeak(canaryStrings: [String], error: Error? = nil) -> Bool {
        let values = recordedEvents.flatMap { event in
            [String(describing: event.name)] + event.fields.flatMap { field in [String(describing: field.key), field.value.text] }
        }
        var all = values
        if let error {
            all.append(error.localizedDescription)
            all.append(String(describing: error))
            if let localized = error as? LocalizedError, let description = localized.errorDescription { all.append(description) }
        }
        return !canaryStrings.contains { canary in all.contains { $0.contains(canary) } }
    }
}

import LokiKit
import VoxCore

public struct LokiVoxTelemetry: VoxTelemetry, Sendable {
    private let service: any TelemetryService
    public init(service: any TelemetryService) { self.service = service }
    public func record(_ event: VoxTelemetryEvent) {
        let properties = Dictionary(event.fields.map { field in
            let value: String
            if case .label(let label) = field.value { value = label.rawLabel }
            else { value = field.value.text }
            return (String(describing: field.key), value)
        }, uniquingKeysWith: { _, latest in latest })
        service.track(name: String(describing: event.name), properties: properties)
    }
}

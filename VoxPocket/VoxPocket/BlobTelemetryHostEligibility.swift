enum BlobTelemetryHostKind: CaseIterable, Equatable, Sendable {
    case interactiveApplication
    case commandLine
    case headless
    case test

    var isEligibleForBlobTelemetry: Bool {
        self == .interactiveApplication
    }
}

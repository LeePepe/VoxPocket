import Dispatch
import Foundation
import LokiKit
import Synchronization

enum BlobProductAction: String, CaseIterable, Sendable {
    case settingsOpened = "settings_opened"
    case fullPanelOpened = "full_panel_opened"
    case quickRecordStarted = "quick_record_started"
    case quickRecordStopped = "quick_record_stopped"
}

enum BlobProductOperation: String, CaseIterable, Sendable {
    case appLaunch = "app_launch"
}

enum BlobTelemetryPolicyFailure: Error, Equatable, Sendable {
    case unknownEvent
    case unknownKey
    case invalidLabel
    case invalidNumber
    case forbiddenValueClass
}

struct BlobProductTelemetryEvent: Sendable {
    private enum Storage: Sendable {
        case userAction(BlobProductAction)
        case performance(BlobProductOperation, Double)
    }

    static let productEventNames: Set<String> = ["product.user_action", "product.performance"]
    private let storage: Storage

    static func userAction(_ action: BlobProductAction) -> Self {
        Self(storage: .userAction(action))
    }

    static func performance(
        _ operation: BlobProductOperation,
        durationMilliseconds: Double
    ) throws -> Self {
        guard durationMilliseconds.isFinite, (0...3_600_000).contains(durationMilliseconds) else {
            throw BlobTelemetryPolicyFailure.invalidNumber
        }
        return Self(storage: .performance(operation, durationMilliseconds))
    }

    var telemetryEvent: TelemetryEvent {
        switch storage {
        case .userAction(let action):
            TelemetryEvent(name: "product.user_action", properties: ["action": action.rawValue])
        case .performance(let operation, let duration):
            TelemetryEvent(
                name: "product.performance",
                properties: ["operation": operation.rawValue, "duration_ms": String(duration)]
            )
        }
    }
}

struct BlobTelemetryMetadata: Equatable, Sendable {
    let app: String
    let build: String
    let version: String

    static func trusted(from bundle: Bundle) -> Self? {
        guard let app = trustedValue("CFBundleName", from: bundle),
              let build = trustedValue("CFBundleVersion", from: bundle),
              let version = trustedValue("CFBundleShortVersionString", from: bundle)
        else { return nil }
        return Self(app: app, build: build, version: version)
    }

    func makePrivacyPolicy() -> AzureBlobPrivacyPolicy {
        AzureBlobPrivacyPolicy(
            events: [
                "product.user_action": [
                    "action": .label(Set(BlobProductAction.allCases.map(\.rawValue)))
                ],
                "product.performance": [
                    "operation": .label(Set(BlobProductOperation.allCases.map(\.rawValue))),
                    "duration_ms": .finiteNumber
                ]
            ],
            apps: [app],
            builds: [build],
            versions: [version]
        )
    }

    private static func trustedValue(_ key: String, from bundle: Bundle) -> String? {
        guard let value = bundle.infoDictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              value == trimmed,
              value.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return value
    }
}

private enum BlobProductTelemetryPolicy {
    static func validate(_ event: TelemetryEvent) throws {
        guard event.timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw BlobTelemetryPolicyFailure.forbiddenValueClass
        }
        switch event.name {
        case "product.user_action":
            guard Set(event.properties.keys) == ["action"] else {
                throw BlobTelemetryPolicyFailure.unknownKey
            }
            guard let action = event.properties["action"],
                  BlobProductAction(rawValue: action) != nil
            else { throw BlobTelemetryPolicyFailure.invalidLabel }
        case "product.performance":
            guard Set(event.properties.keys) == ["operation", "duration_ms"] else {
                throw BlobTelemetryPolicyFailure.unknownKey
            }
            guard let operation = event.properties["operation"],
                  BlobProductOperation(rawValue: operation) != nil
            else { throw BlobTelemetryPolicyFailure.invalidLabel }
            guard let value = event.properties["duration_ms"],
                  let duration = Double(value),
                  duration.isFinite,
                  (0...3_600_000).contains(duration)
            else { throw BlobTelemetryPolicyFailure.invalidNumber }
        default:
            throw BlobTelemetryPolicyFailure.unknownEvent
        }
    }
}

enum BlobTelemetryBootstrapOutcome: Equatable, Sendable {
    case ready
    case consentRequired
    case ineligibleHost
    case configurationDisabled
    case invalidConfiguration(BlobTelemetryConfigurationFailure)
    case constructionFailed

    var diagnostic: String {
        switch self {
        case .ready: "blob_ready"
        case .consentRequired: "blob_consent_required"
        case .ineligibleHost: "blob_host_ineligible"
        case .configurationDisabled: "blob_configuration_disabled"
        case .invalidConfiguration(let failure): failure.diagnostic
        case .constructionFailed: "blob_construction_failed"
        }
    }
}

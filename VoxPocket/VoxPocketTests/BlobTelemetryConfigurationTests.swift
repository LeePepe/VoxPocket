import Foundation
import Testing
@testable import VoxPocket

struct BlobTelemetryConfigurationTests {
    private let endpoint = "https://telemetry.example.invalid/container"
    private let sas = "sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake%2Bonly%2F%3D"
    private let policyCreateCommand = [
        "az", "storage", "container", "policy", "create",
        "--account-name", "<storage-account>",
        "--container-name", "<container>",
        "--name", "<policy-name>",
        "--permissions", "c",
        "--expiry", "<YYYY-MM-DDTHH:MM:SSZ>",
        "--auth-mode", "key",
        "--output", "none"
    ]

    @Test func missingEmptyAndUnexpandedValuesAreDisabled() {
        let fixtures: [[String: Any]] = [
            [:],
            ["LokiKitBlobEndpoint": "", "LokiKitBlobSAS": sas],
            ["LokiKitBlobEndpoint": endpoint, "LokiKitBlobSAS": "   "],
            ["LokiKitBlobEndpoint": "$(TELEMETRY_BLOB_ENDPOINT)", "LokiKitBlobSAS": sas],
            ["LokiKitBlobEndpoint": endpoint, "LokiKitBlobSAS": "$(TELEMETRY_BLOB_SAS)"]
        ]

        for fixture in fixtures {
            #expect(BlobTelemetryConfiguration(testingInfoDictionary: fixture) == .disabled)
        }
    }

    @Test func storedPolicyCreateOnlyShapeIsAccepted() {
        let configuration = BlobTelemetryConfiguration(testingInfoDictionary: [
            "LokiKitBlobEndpoint": endpoint,
            "LokiKitBlobSAS": sas
        ])

        guard case .enabled(let enabled) = configuration else {
            Issue.record("Expected enabled configuration")
            return
        }
        #expect(enabled.endpoint.absoluteString == endpoint)
        #expect(enabled.sasQuery == sas)
    }

    @Test func storedPolicyCreateCommandIsCreateOnlyAndNeverGeneratesAToken() throws {
        let permissionIndex = try #require(policyCreateCommand.firstIndex(of: "--permissions"))
        let authModeIndex = try #require(policyCreateCommand.firstIndex(of: "--auth-mode"))
        #expect(policyCreateCommand[permissionIndex + 1] == "c")
        #expect(policyCreateCommand[authModeIndex + 1] == "key")
        #expect(policyCreateCommand.prefix(5) == ["az", "storage", "container", "policy", "create"])
        for forbidden in [
            "generate-sas", "--as-user", "--account-key", "--sas-token",
            "--connection-string", "sig", "--signature", "signature"
        ] {
            #expect(!policyCreateCommand.contains(forbidden))
        }
        #expect(policyCreateCommand.allSatisfy {
            !$0.contains("PRIVATE_") && !$0.contains("SECRET_")
        })
    }

    @Test(arguments: [
        "sv=2023-11-03&sr=c&si=policy&spr=https&sig=fake&sp=cw",
        "sv=2023-11-03&sr=b&si=policy&spr=https&sig=fake",
        "sv=2023-11-03&sr=c&spr=https&sig=fake",
        "sv=2023-11-03&sr=c&si=policy&spr=https",
        "sv=2023-11-03&sr=c&si=policy&spr=https&sig=fake&skoid=forbidden",
        "sv=2023-11-03&sr=c&si=policy&spr=https&sig=fake&unknown=value",
        "sv=2023-11-03&sr=c&si=policy&spr=http&sig=fake",
        "sv=2023-11-03&sr=c&si=policy&spr=https&sig=bad value",
        "sv=2023-11-03&sr=c&si=policy&spr=https&sig=bad%escape"
    ])
    func broaderOrUnsafeSASShapesAreRejected(_ candidate: String) {
        let configuration = BlobTelemetryConfiguration(testingInfoDictionary: [
            "LokiKitBlobEndpoint": endpoint,
            "LokiKitBlobSAS": candidate
        ])
        #expect(configuration == .invalid(.invalidSAS))
        #expect(configuration.diagnostic == "blob_configuration_invalid_sas")
        #expect(!configuration.diagnostic.contains(candidate))
    }

    @Test func presentInvalidEndpointReturnsOnlyFixedFailure() {
        let supplied = "http://PRIVATE_ENDPOINT_SENTINEL/container"
        let configuration = BlobTelemetryConfiguration(testingInfoDictionary: [
            "LokiKitBlobEndpoint": supplied,
            "LokiKitBlobSAS": sas
        ])

        #expect(configuration == .invalid(.invalidEndpoint))
        #expect(configuration.diagnostic == "blob_configuration_invalid_endpoint")
        #expect(!configuration.diagnostic.contains(supplied))
    }
}

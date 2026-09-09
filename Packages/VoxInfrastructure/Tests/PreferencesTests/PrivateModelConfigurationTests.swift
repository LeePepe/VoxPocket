import Foundation
import XCTest
@testable import Preferences

final class PrivateModelConfigurationTests: XCTestCase {
    private let fixture: [String: String] = [
        "endpoint": "https://example.invalid", "apiKey": "test-config-key",
        "transcriptionDeployment": "fixture-asr", "refinementDeployment": "fixture-llm"
    ]

    func testMissingFileKeepsEnvironmentUnchanged() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = ["AZURE_API_KEY": "test-env-key", "PATH": "/fixture"]
        let result = try await DefaultPrivateModelConfigurationLoader(fileURL: url).load(environment: environment)
        XCTAssertFalse(result.loadedPrivateFile)
        XCTAssertEqual(result.environmentValues, environment)
    }

    func testValidFileWorksWithoutEnvironmentAndIsExcludedFromBackup() async throws {
        let url = try makeFile(data: encoded(fixture))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let result = try await DefaultPrivateModelConfigurationLoader(fileURL: url).load(environment: [:])
        XCTAssertTrue(result.loadedPrivateFile)
        XCTAssertEqual(result.environmentValues["AZURE_OPENAI_ENDPOINT"], "https://example.invalid")
        XCTAssertEqual(result.environmentValues["whisperkey"], "test-config-key")
        XCTAssertEqual(result.environmentValues["kimikey"], "test-config-key")
        XCTAssertEqual(result.environmentValues["AZURE_TRANSCRIPTION_DEPLOYMENT"], "fixture-asr")
        XCTAssertEqual(result.environmentValues["AZURE_FOUNDRY_MODEL"], "fixture-llm")
        XCTAssertFalse(String(describing: result).contains("test-config-key"))
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testEnvironmentAndLegacyAliasesOverrideFileWithoutGlobalMutation() async throws {
        let url = try makeFile(data: encoded(fixture))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let before = ProcessInfo.processInfo.environment
        let environment = ["AZURE_API_KEY": "test-shared", "whisperkey": "test-audio", "kimikey": "  ", "VOX_AZURE_FOUNDRY_API_KEY": "test-text", "AZURE_FOUNDRY_MODEL": "override-llm"]
        let result = try await DefaultPrivateModelConfigurationLoader(fileURL: url).load(environment: environment)
        XCTAssertEqual(result.environmentValues["AZURE_API_KEY"], "test-shared")
        XCTAssertEqual(result.environmentValues["whisperkey"], "test-audio")
        XCTAssertEqual(result.environmentValues["kimikey"], "test-text")
        XCTAssertEqual(result.environmentValues["AZURE_FOUNDRY_MODEL"], "override-llm")
        XCTAssertEqual(ProcessInfo.processInfo.environment, before)
    }

    func testUnsafePermissionsRejected() async throws {
        let url = try makeFile(data: encoded(fixture), mode: 0o644)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await expectFailure(url, .unsafeFile)
    }

    func testSymbolicLinkRejected() async throws {
        let url = try makeFile(data: encoded(fixture))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let link = url.deletingLastPathComponent().appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        await expectFailure(link, .unreadable)
    }

    func testMalformedJSONDoesNotLeakBody() async throws {
        let url = try makeFile(data: Data("PRIVATE_SECRET_INVALID_JSON".utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await expectFailure(url, .invalidJSON)
    }

    func testOversizedFileRejected() async throws {
        let url = try makeFile(data: Data(repeating: 65, count: 65_537))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await expectFailure(url, .oversized)
    }

    func testInvalidEndpointsAndKeysAndDeploymentsAreRejected() throws {
        let invalid: [(String, String)] = [
            ("endpoint", "http://example.invalid"), ("endpoint", "https://user:password@example.invalid"),
            ("endpoint", "https://example.invalid/path"), ("endpoint", "https://example.invalid?q=1"),
            ("endpoint", "https://example.invalid#secret"), ("apiKey", "  "), ("apiKey", "key\nheader"),
            ("transcriptionDeployment", "../escape"), ("refinementDeployment", "bad\n"),
            ("refinementDeployment", String(repeating: "a", count: 129))
        ]
        for (field, value) in invalid {
            var fields = fixture
            fields[field] = value
            let configuration = try PrivateModelConfiguration.decode(encoded(fields))
            XCTAssertThrowsError(try configuration.environmentDefaults()) { error in
                XCTAssertEqual(error as? PrivateModelConfigurationError, .invalidFields)
            }
        }
    }

    func testNonRegularFileIsRejected() async throws {
        let url = try makeFile(data: encoded(fixture))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await expectFailure(url.deletingLastPathComponent(), .unsafeFile)
    }

    private func expectFailure(_ url: URL, _ expected: PrivateModelConfigurationError) async {
        do {
            _ = try await DefaultPrivateModelConfigurationLoader(fileURL: url).load(environment: [:])
            XCTFail("Expected a safe configuration error")
        } catch {
            XCTAssertEqual(error as? PrivateModelConfigurationError, expected)
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_SECRET"))
        }
    }

    private func encoded(_ fields: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["azure": fields])
    }

    private func makeFile(data: Data, mode: Int = 0o600) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.json")
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url
    }
}

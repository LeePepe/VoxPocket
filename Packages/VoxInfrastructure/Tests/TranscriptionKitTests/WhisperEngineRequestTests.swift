import Foundation
import Synchronization
import XCTest
@testable import TranscriptionKit

final class WhisperEngineRequestTests: XCTestCase {
    func testRecordingTemporaryFileIsInsideApplicationData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try MicrophoneRecorder.makeRecordingFileURL(applicationSupport: root)
        let second = try MicrophoneRecorder.makeRecordingFileURL(applicationSupport: root)
        XCTAssertEqual(first.deletingLastPathComponent(), root.appendingPathComponent("VoxPocket/TemporaryAudio", isDirectory: true))
        XCTAssertEqual(first.pathExtension, "wav")
        XCTAssertNotEqual(first, second)
        let directory = first.deletingLastPathComponent()
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
    }

    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        static let status = Mutex(200)
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "test-key")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let code = Self.status.withLock { $0 }
            let body = code == 200 ? #"{"text":"几点开始？"}"# : #"{"error":"PRIVATE_AUDIO_TEXT"}"#
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testCloudTranscriptPreservesQuestionMarkAndSanitizesErrors() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data("synthetic-fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let engine = WhisperEngine(config: .init(endpoint: URL(string: "https://example.invalid/audio/transcriptions")!, apiKey: "test-key"), session: URLSession(configuration: configuration))
        MockURLProtocol.status.withLock { $0 = 200 }
        let result = try await engine.transcribe(fileURL: file, language: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(result, "几点开始？")
        MockURLProtocol.status.withLock { $0 = 400 }
        do {
            _ = try await engine.transcribe(fileURL: file, language: Locale(identifier: "zh-Hans"))
            XCTFail("Expected failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_AUDIO_TEXT"))
        }
    }
}

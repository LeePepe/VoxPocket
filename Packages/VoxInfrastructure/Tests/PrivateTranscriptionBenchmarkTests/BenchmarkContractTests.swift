#if os(macOS)
import Foundation
import Speech
import XCTest
@testable import TranscriptionKit

final class BenchmarkContractTests: XCTestCase {
    func testScoringDeterministicAndMixedEnglishIsOneToken() {
        let same = BenchmarkScoring.score(reference: "你好，TEST。", recognized: "你好 test。")
        XCTAssertEqual(same.cer, 0)
        XCTAssertEqual(same.mixedTokenErrorRate, 0)
        XCTAssertTrue(same.preservesTest)
        XCTAssertEqual(same.punctuationEdits, 1)
        let changed = BenchmarkScoring.score(reference: "你好 test", recognized: "你坏 text")
        XCTAssertEqual(changed.cer, 2.0 / 6, accuracy: 0.0001)
        XCTAssertEqual(changed.mixedTokenErrorRate, 2.0 / 3, accuracy: 0.0001)
        XCTAssertFalse(changed.preservesTest)
        XCTAssertEqual(BenchmarkScoring.distance([Int](), [1, 2]), 2)
    }

    func testSilentLoggerDoesNotEvaluateSensitiveMessage() {
        let logger = SilentBenchmarkLogger()
        func forbidden() -> String { XCTFail("Message must not be evaluated"); return "synthetic-only" }
        logger.log(.critical, forbidden(), file: "", function: "", line: 0)
        logger.log(.critical, forbidden(), context: ["synthetic": "sentinel"], file: "", function: "", line: 0)
        logger.minimumLevel = .debug
        XCTAssertEqual(logger.minimumLevel, .debug)
    }

    func testPrivacyProjectionHasNoTranscriptFields() throws {
        let summary = BenchmarkSummary(provider: "azure", sourceSHA: String(repeating: "a", count: 40),
            dependencySHA: String(repeating: "b", count: 40), processID: 1, generatedAt: Date(),
            inputPacing: "batch", actualAppleRoute: "unknown", cloudBackingModel: "unknown", cachePresent: false,
            audioSeconds: 1, runs: [BenchmarkRun(iteration: 0, cold: true)])
        let report = PrivateBenchmarkReport(summary: summary, reference: "PRIVATE_SENTINEL",
                                           recognized: ["PRIVATE_SENTINEL"], merged: [], refined: [])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(report.summary), as: UTF8.self).contains("PRIVATE_SENTINEL"))
        XCTAssertNil(summary.runs[0].firstPartialSeconds)
        XCTAssertNil(summary.runs[0].score)
    }

    func testProtectedIORejectsPermissionsSymlinksEscapeAndOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("results")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = output.appendingPathComponent("synthetic.json")
        try ProtectedBenchmarkFiles.write(["value": 3], to: file, beneath: root)
        XCTAssertNoThrow(try ProtectedBenchmarkFiles.read(file, beneath: root, maximumBytes: 1024))
        XCTAssertThrowsError(try ProtectedBenchmarkFiles.write(["value": 4], to: file, beneath: root))
        XCTAssertThrowsError(try ProtectedBenchmarkFiles.read(file, beneath: output.appendingPathComponent("wrong"), maximumBytes: 1024))
        let link = output.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try ProtectedBenchmarkFiles.read(link, beneath: root, maximumBytes: 1024))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try ProtectedBenchmarkFiles.read(file, beneath: root, maximumBytes: 1024))
    }

    func testCanonicalAudioIsByteEquivalentForFileAndBuffer() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic.wav")
        let canonical = BenchmarkAudio(samples: [0, 0.5, -0.5, 0.99, -0.99] + Array(repeating: 0, count: 15995)).canonicalized()
        try canonical.wav().write(to: url)
        let fromFile = try BenchmarkAudio.decode(url)
        XCTAssertEqual(fromFile.samples, canonical.samples)
        XCTAssertEqual(fromFile.duration, 1)
    }

    func testProductionApplePolicyAndGroupPlan() {
        let request = DefaultAppleSpeechRequestFactory.makeRequest()
        XCTAssertTrue(request.shouldReportPartialResults)
        XCTAssertTrue(request.addsPunctuation)
        XCTAssertFalse(request.requiresOnDeviceRecognition)
        XCTAssertEqual(BenchmarkGroup.allCases.count, 8)
        XCTAssertFalse(BenchmarkGroup.localBase.usesCloud)
        XCTAssertTrue(BenchmarkGroup.hybridBase.isHybrid)
        XCTAssertNil(BenchmarkGroup.azure.localModel)
    }
}
#endif

import TranscriptionKitCombine
import VoxCore
import Foundation
import XCTest
@testable import TranscriptionKit

final class SpeechGoldenTraceTests: XCTestCase {
    @MainActor func testAllSpeechAdaptersUseInjectedAuthorizationAndAvailability() async throws {
        for allowed in [false, true] {
            for available in [false, true] {
                let calls = GoldenEvents()
                let recorder = try GoldenAudioSource(calls: calls)
                defer { try? FileManager.default.removeItem(at: recorder.file) }
                let recognizer = GoldenRecognizer(calls: calls, available: available)
                let authorization = GoldenSpeechAuthorization(allowed: allowed, calls: calls)
                let engine = GoldenLocalEngine(calls: calls)
                let transcribers: [any TranscriptionCoordinator] = [
                    CombineTranscriptionCoordinator.wrap(AppleSpeechTranscriber(recorder: recorder, speechRecognizer: recognizer,
                                           speechAuthorizationProvider: authorization, logger: GoldenLogger(), storageLocations: testStorageLocations)),
                    CombineTranscriptionCoordinator.wrap(HybridWhisperTranscriber(recorder: recorder, speechRecognizer: recognizer,
                                              speechAuthorizationProvider: authorization, whisperEngine: GoldenBatch(calls: calls),
                                              realtimeSessionMaker: GoldenRealtime(calls: calls), logger: GoldenLogger(), storageLocations: testStorageLocations)),
                    CombineTranscriptionCoordinator.wrap(HybridLocalWhisperTranscriber(recorder: recorder, speechRecognizer: recognizer,
                                                   speechAuthorizationProvider: authorization, batchTranscriber: GoldenBatch(calls: calls),
                                                   whisperEngine: engine, config: .init(preloadOnStart: false), logger: GoldenLogger(), storageLocations: testStorageLocations))
                ]
                for transcriber in transcribers {
                    let permission = await transcriber.speechRecognitionService.requestPermission()
                    let availability = await transcriber.speechRecognitionService.checkAvailability()
                    XCTAssertEqual(permission, allowed)
                    XCTAssertEqual(availability, allowed && available)
                }
                XCTAssertEqual(calls.values.filter { $0.hasPrefix("speech.permission:") }.count, 3)
            }
        }
    }

    func testLocalBatchAdapterUsesConfigurationLanguageHint() async throws {
        let calls = GoldenEvents()
        let config = LocalWhisperKitConfig(preloadOnStart: false)
        let adapter = LocalWhisperBatchAdapter(engine: GoldenLocalEngine(calls: calls), config: config)
        for language in ["zh-Hans", "en-US", "fr-FR"] {
            let locale = Locale(identifier: language)
            let output = try await adapter.transcribe(fileURL: URL(fileURLWithPath: "/synthetic.wav"), language: locale)
            XCTAssertEqual(output, "synthetic local")
            XCTAssertEqual(calls.values.last, "local.transcribe:\(config.languageHint(for: locale) ?? "nil")")
        }
    }

    @MainActor func testRealTranscriberGolden() async throws {
        var traces: [[String: Any]] = []
        for scenario in ["speechAuthDenied", "micAuthDenied", "normalRecognition", "recognizerUnavailable", "recognizerThrows"] {
            traces.append(try await appleTrace(scenario))
        }
        for scenario in ["realtimeSuccess", "realtimeFallback", "silenceSkip", "withMerger", "withoutMerger", "quickDiscard"] {
            traces.append(try await hybridTrace(scenario))
        }
        traces.append(try await isolationTrace())
        try assertGolden(["schema": "golden-trace/v1", "kind": "speech", "traces": traces], name: "golden_c_speech")
    }

    @MainActor private func appleTrace(_ scenario: String) async throws -> [String: Any] {
        let calls = GoldenEvents()
        let recorder = try GoldenAudioSource(permission: scenario != "micAuthDenied", calls: calls)
        let recognizer = GoldenRecognizer(calls: calls, available: scenario != "recognizerUnavailable",
                                         startupFails: scenario == "recognizerThrows")
        let logger = GoldenLogger()
        let transcriber = CombineTranscriptionCoordinator.wrap(AppleSpeechTranscriber(recorder: recorder, speechRecognizer: recognizer,
                                                speechAuthorizationProvider: GoldenSpeechAuthorization(allowed: scenario != "speechAuthDenied", calls: calls),
                                                logger: logger, storageLocations: testStorageLocations))
        let probe = GoldenSpeechProbe(transcriber)
        let permission = await transcriber.speechRecognitionService.requestPermission()
        let available = await transcriber.speechRecognitionService.checkAvailability()
        XCTAssertEqual(permission, scenario != "speechAuthDenied")
        XCTAssertEqual(available, scenario != "speechAuthDenied" && scenario != "recognizerUnavailable")
        var errorCode: Int?
        do {
            try await transcriber.start(language: Locale(identifier: "zh-Hans"))
            XCTAssertEqual(scenario, "normalRecognition")
            XCTAssertTrue(transcriber.isTranscribing)
            await probe.waitFor("state:recording")
            recorder.level(0.25)
            await probe.waitFor("level:0.25")
            recognizer.emit("synthetic partial")
            await probe.waitFor("live:partial:synthetic partial:nil")
            transcriber.pause()
            await probe.waitFor("state:paused")
            XCTAssertEqual(transcriber.audioCaptureService.state, .paused)
            transcriber.resume()
            await probe.waitFor("state:recording", count: 2)
            XCTAssertEqual(transcriber.audioCaptureService.state, .recording)
            recognizer.emit("synthetic final", final: true)
            await probe.waitFor("final:synthetic final")
            await transcriber.stop()
        } catch { errorCode = (error as NSError).code }
        let idleCount = scenario == "normalRecognition" ? 2 : scenario == "recognizerThrows" ? 3 : 2
        await probe.waitFor("state:idle", count: idleCount)
        let expectedError: Int? = scenario == "normalRecognition" ? nil : scenario == "recognizerUnavailable" ? -2 : scenario == "recognizerThrows" ? -7 : -1
        XCTAssertEqual(errorCode, expectedError)
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.file.path))
        XCTAssertEqual(probe.values.filter { $0.hasPrefix("final:") }.count, scenario == "normalRecognition" ? 1 : 0)
        return ["scenario": scenario, "calls": calls.values, "events": probe.values,
                "errorCode": errorCode as Any? ?? NSNull(), "fileRemoved": !FileManager.default.fileExists(atPath: recorder.file.path),
                "logs": logger.messages, "logContextKeys": logger.contextKeys, "telemetry": [String]()]
    }

    @MainActor private func hybridTrace(_ scenario: String) async throws -> [String: Any] {
        let calls = GoldenEvents()
        let recorder = try GoldenAudioSource(calls: calls)
        let recognizer = GoldenRecognizer(calls: calls)
        let pipeline = GoldenRealtime(calls: calls, minimumAudio: !["silenceSkip", "quickDiscard"].contains(scenario),
                                      fails: scenario == "realtimeFallback")
        let config = try AzureRealtimeTranscriptionConfig(endpoint: XCTUnwrap(URL(string: "https://example.invalid")),
                                                          apiKey: "fixture-key", deployment: "example-live")
        let logger = GoldenLogger()
        let realtimeEnabled = ["realtimeSuccess", "realtimeFallback", "silenceSkip", "quickDiscard"].contains(scenario)
        let transcriber = CombineTranscriptionCoordinator.wrap(HybridWhisperTranscriber(recorder: recorder, speechRecognizer: recognizer,
                                                   speechAuthorizationProvider: GoldenSpeechAuthorization(allowed: true, calls: calls),
                                                   whisperEngine: GoldenBatch(calls: calls), realtimeSessionMaker: pipeline,
                                                   realtimeConfig: realtimeEnabled ? config : nil, logger: logger,
                                                   merger: scenario == "withMerger" ? GoldenMerger(calls: calls) : nil, storageLocations: testStorageLocations))
        let probe = GoldenSpeechProbe(transcriber)
        if scenario == "quickDiscard" { try transcriber.prepareQuickRecording() }
        try await transcriber.start(language: Locale(identifier: "zh-Hans"))
        await probe.waitFor("state:recording")
        if !["silenceSkip", "quickDiscard"].contains(scenario) {
            recognizer.emit("synthetic apple")
            await probe.waitFor("live:partial:synthetic apple:nil")
        }
        if ["realtimeSuccess", "realtimeFallback"].contains(scenario) {
            pipeline.partial()
            await probe.waitFor("live:partial:synthetic cloud partial:nil")
            recognizer.emit("synthetic newer apple")
            if scenario == "realtimeFallback" {
                pipeline.fallback()
                await probe.waitFor("live:partial:synthetic newer apple:nil")
            }
        }
        if scenario == "quickDiscard" {
            let snapshot = try transcriber.freezeQuickRecordingRelease()
            XCTAssertFalse(snapshot.hasRecognizedSpeech)
            try await transcriber.completeQuickRecordingRelease(snapshot)
            XCTAssertTrue(calls.values.contains("realtime.cancelQuickRecording"))
        } else { await transcriber.stop() }
        await probe.waitFor("state:idle", count: 2)
        if !["silenceSkip", "quickDiscard"].contains(scenario) {
            let final = scenario == "withMerger" ? "synthetic merged" : scenario == "realtimeSuccess" ? "synthetic cloud final" : "synthetic batch"
            await probe.waitFor("final:" + final)
        }
        let batchCalls = calls.values.filter { $0.hasPrefix("batch.transcribe:") }.count
        XCTAssertEqual(batchCalls, ["realtimeFallback", "withMerger", "withoutMerger"].contains(scenario) ? 1 : 0)
        let finals = probe.values.filter { $0.hasPrefix("final:") }
        XCTAssertEqual(finals.count, ["silenceSkip", "quickDiscard"].contains(scenario) ? 0 : 1)
        if scenario == "withMerger" { XCTAssertFalse(probe.values.contains("live:final:synthetic merged:nil")) }
        if scenario == "withoutMerger" { XCTAssertTrue(probe.values.contains("live:final:synthetic batch:nil")) }
        if scenario == "realtimeFallback" { XCTAssertTrue(probe.values.contains("live:partial:synthetic newer apple:nil")) }
        XCTAssertFalse(transcriber.isTranscribing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.file.path))
        return ["scenario": scenario, "calls": calls.values, "events": probe.values, "batchCalls": batchCalls,
                "fileRemoved": !FileManager.default.fileExists(atPath: recorder.file.path), "logs": logger.messages,
                "logContextKeys": logger.contextKeys, "telemetry": [String]()]
    }

    @MainActor private func isolationTrace() async throws -> [String: Any] {
        let mainCalls = GoldenEvents(); let quickCalls = GoldenEvents()
        let mainRecorder = try GoldenAudioSource(calls: mainCalls); let quickRecorder = try GoldenAudioSource(calls: quickCalls)
        let mainRecognizer = GoldenRecognizer(calls: mainCalls); let quickRecognizer = GoldenRecognizer(calls: quickCalls)
        let main = CombineTranscriptionCoordinator.wrap(AppleSpeechTranscriber(recorder: mainRecorder, speechRecognizer: mainRecognizer,
                                          speechAuthorizationProvider: GoldenSpeechAuthorization(allowed: true, calls: mainCalls), logger: GoldenLogger(), storageLocations: testStorageLocations))
        let quick = CombineTranscriptionCoordinator.wrap(AppleSpeechTranscriber(recorder: quickRecorder, speechRecognizer: quickRecognizer,
                                           speechAuthorizationProvider: GoldenSpeechAuthorization(allowed: true, calls: quickCalls), logger: GoldenLogger(), storageLocations: testStorageLocations))
        let mainProbe = GoldenSpeechProbe(main); let quickProbe = GoldenSpeechProbe(quick)
        try quick.prepareQuickRecording()
        try await main.start(language: Locale(identifier: "en"))
        try await quick.start(language: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(main.isTranscribing && quick.isTranscribing)
        await mainProbe.waitFor("state:recording")
        await quickProbe.waitFor("state:recording")
        mainRecognizer.emit("synthetic main")
        await mainProbe.waitFor("live:partial:synthetic main:nil")
        quickRecognizer.emit("synthetic quick", final: true)
        await quickProbe.waitFor("final:synthetic quick")
        let frozen = try quick.freezeQuickRecordingRelease()
        XCTAssertTrue(frozen.hasRecognizedSpeech)
        try await quick.completeQuickRecordingRelease(frozen)
        XCTAssertTrue(main.isTranscribing)
        quickRecognizer.emit("synthetic late quick")
        await quickProbe.waitFor("live:partial:synthetic late quick:nil")
        mainRecognizer.emit("synthetic main final", final: true)
        await main.stop()
        await mainProbe.waitFor("final:synthetic main final")
        await mainProbe.waitFor("state:idle", count: 2)
        await quickProbe.waitFor("state:idle", count: 2)
        XCTAssertTrue(quickProbe.values.contains("live:partial:synthetic late quick:nil"))
        XCTAssertFalse(mainProbe.values.contains { $0.contains("synthetic quick") })
        XCTAssertFalse(quickProbe.values.contains { $0.contains("synthetic main") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: mainRecorder.file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quickRecorder.file.path))
        return ["scenario": "mainAndQuickIsolation", "mainCalls": mainCalls.values, "quickCalls": quickCalls.values,
                "mainEvents": mainProbe.values, "quickEvents": quickProbe.values, "recognizedAtRelease": frozen.hasRecognizedSpeech]
    }
}

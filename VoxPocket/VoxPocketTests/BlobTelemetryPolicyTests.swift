import Foundation
import LokiKit
import Synchronization
import Testing
@testable import VoxPocket
import zlib

@Suite(.serialized)
struct BlobTelemetryPolicyTests {
    @Test func typedEventsProduceOnlyTheTwoApprovedShapes() throws {
        let action = BlobProductTelemetryEvent.userAction(.settingsOpened)
        let performance = try BlobProductTelemetryEvent.performance(.appLaunch, durationMilliseconds: 42.5)

        #expect(action.telemetryEvent.name == "product.user_action")
        #expect(action.telemetryEvent.properties == ["action": "settings_opened"])
        #expect(performance.telemetryEvent.name == "product.performance")
        #expect(performance.telemetryEvent.properties == ["operation": "app_launch", "duration_ms": "42.5"])
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.1, 3_600_000.1])
    func performanceRejectsInvalidNumbers(_ value: Double) {
        #expect(throws: BlobTelemetryPolicyFailure.invalidNumber) {
            try BlobProductTelemetryEvent.performance(.appLaunch, durationMilliseconds: value)
        }
    }

    @Test func productSurfaceCannotConstructHeartbeatOrFreeFormValues() {
        #expect(BlobProductTelemetryEvent.productEventNames == Set(["product.user_action", "product.performance"]))
        #expect(BlobProductAction.allCases.map(\.rawValue) == [
            "settings_opened", "full_panel_opened", "quick_record_started", "quick_record_stopped"
        ])
        #expect(BlobProductOperation.allCases.map(\.rawValue) == ["app_launch"])
    }

    @Test func syntheticProductionFactoryDerivesAdapterAndAllowlistMetadataFromTrustedBundle() async throws {
        let fixture = try BlobPublicBoundaryFixture(metadata: [
            "CFBundleName": "TrustedSyntheticApp",
            "CFBundleVersion": "73",
            "CFBundleShortVersionString": "9.4"
        ])
        defer { fixture.remove() }
        let bootstrap = BlobTelemetryBootstrap.testingProduction(
            bundle: fixture.bundle,
            host: .interactiveApplication,
            isConsented: true,
            storeDirectory: fixture.store,
            identityProvider: { UUID(uuidString: "11111111-1111-4111-8111-111111111111")! }
        )

        let service = try await Task.detached { try bootstrap.makeTestingService() }.value
        let adapter = try #require(service as? AzureBlobTelemetryService)
        let heartbeat = try #require(adapter.diagnostics.lastHeartbeat)

        #expect(heartbeat.properties["app"] == "TrustedSyntheticApp")
        #expect(heartbeat.properties["build"] == "73")
        #expect(heartbeat.properties["version"] == "9.4")
        #expect(adapter.diagnostics.rejectedEventCount == 0)
    }

    @Test func syntheticProductionFactoryRejectsMissingOrEmptyTrustedMetadataBeforeSideEffects() async throws {
        let invalidMetadata: [[String: String]] = [
            ["CFBundleVersion": "73", "CFBundleShortVersionString": "9.4"],
            ["CFBundleName": "", "CFBundleVersion": "73", "CFBundleShortVersionString": "9.4"],
            ["CFBundleName": "TrustedSyntheticApp", "CFBundleShortVersionString": "9.4"],
            ["CFBundleName": "TrustedSyntheticApp", "CFBundleVersion": " \n", "CFBundleShortVersionString": "9.4"],
            ["CFBundleName": "TrustedSyntheticApp", "CFBundleVersion": "73"],
            ["CFBundleName": "TrustedSyntheticApp", "CFBundleVersion": "73", "CFBundleShortVersionString": ""]
        ]

        for metadata in invalidMetadata {
            let fixture = try BlobPublicBoundaryFixture(metadata: metadata)
            defer { fixture.remove() }
            BlobPublicBoundaryProtocol.reset(mode: .status(201))
            let identityRequests = Mutex(0)
            let coordinator = TelemetryLifecycleCoordinator(isEnabled: false) { NoopTelemetryService() }
            let bootstrap = BlobTelemetryBootstrap.testingProduction(
                bundle: fixture.bundle,
                host: .interactiveApplication,
                isConsented: true,
                storeDirectory: fixture.store,
                identityProvider: {
                    identityRequests.withLock { $0 += 1 }
                    return UUID()
                }
            )

            #expect(await coordinator.bootstrapBlob(bootstrap) == .constructionFailed)
            #expect(identityRequests.withLock { $0 } == 0)
            #expect(!FileManager.default.fileExists(atPath: fixture.store.path))
            #expect(BlobPublicBoundaryProtocol.requests.isEmpty)
        }
    }

    @Test func publicAdapterRejectsCompletePrivacyMatrixBeforePersistenceOrTransport() async throws {
        let fixture = try BlobPublicBoundaryFixture()
        defer { fixture.remove() }
        BlobPublicBoundaryProtocol.reset(mode: .status(201))
        let service = try fixture.makeService()
        let cases: [(event: TelemetryEvent, sentinel: String)] = [
            (.init(name: "UNKNOWN_NAME_SENTINEL", properties: ["action": "settings_opened"]), "UNKNOWN_NAME_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "unknown": "UNKNOWN_KEY_SENTINEL"
            ]), "UNKNOWN_KEY_SENTINEL"),
            (.init(name: "product.user_action", properties: ["action": "INVALID_LABEL_SENTINEL"]), "INVALID_LABEL_SENTINEL"),
            (.init(name: "product.performance", properties: [
                "operation": "app_launch", "duration_ms": "INVALID_NUMBER_SENTINEL"
            ]), "INVALID_NUMBER_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "audio": "AUDIO_SENTINEL"
            ]), "AUDIO_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "transcript": "TRANSCRIPT_SENTINEL"
            ]), "TRANSCRIPT_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "refined_text": "REFINED_TEXT_SENTINEL"
            ]), "REFINED_TEXT_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "prompt": "PROMPT_SENTINEL"
            ]), "PROMPT_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "error": "ERROR_SENTINEL"
            ]), "ERROR_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "endpoint": "ENDPOINT_SENTINEL"
            ]), "ENDPOINT_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "sas": "SAS_SENTINEL"
            ]), "SAS_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "credential": "CREDENTIAL_SENTINEL"
            ]), "CREDENTIAL_SENTINEL"),
            (.init(name: "product.user_action", properties: [
                "action": "settings_opened", "uuid": "11111111-1111-4111-8111-111111111111"
            ]), "11111111-1111-4111-8111-111111111111"),
            (.init(
                name: "product.user_action",
                properties: ["action": "settings_opened"],
                timestamp: Date(timeIntervalSinceReferenceDate: .infinity)
            ), "invalid_timestamp"),
        ]

        for (offset, testCase) in cases.enumerated() {
            service.track(testCase.event)
            let diagnostics = service.diagnostics
            #expect(diagnostics.rejectedEventCount == offset + 1)
            #expect(diagnostics.lastError == .privacyRejected)
            #expect(!String(describing: diagnostics.lastError).contains(testCase.sentinel))
            #expect(fixture.persistedBytes().allSatisfy {
                $0.range(of: Data(testCase.sentinel.utf8)) == nil
            })
        }

        await service.flush()

        #expect(BlobPublicBoundaryProtocol.requests.count == 1)
        let request = try #require(BlobPublicBoundaryProtocol.requests.first)
        let requestBytes = try gunzipBlobRequest(request.body)
        let events = try decodeBlobEvents(requestBytes)
        #expect(events.map(\.name) == ["telemetry.heartbeat"])
        for testCase in cases {
            #expect(requestBytes.range(of: Data(testCase.sentinel.utf8)) == nil)
        }
    }

    @Test func productionTrackBoundaryAndSDKOwnedHeartbeatReachPublicRequest() async throws {
            let fixture = try BlobPublicBoundaryFixture()
            defer { fixture.remove() }
            BlobPublicBoundaryProtocol.reset(mode: .status(201))
            let service = Mutex<AzureBlobTelemetryService?>(nil)
            let constructionWasOnMain = Mutex<Bool?>(nil)
            let coordinator = TelemetryLifecycleCoordinator(isEnabled: false) { NoopTelemetryService() }
            let bootstrap = fixture.bootstrap {
                constructionWasOnMain.withLock { $0 = Thread.isMainThread }
                let adapter = try fixture.makeService()
                service.withLock { $0 = adapter }
                return adapter
            }

            #expect(await coordinator.bootstrapBlob(bootstrap) == .ready)
            let adapter = try #require(service.withLock { $0 })
            let heartbeat = try #require(adapter.diagnostics.lastHeartbeat)
            #expect(constructionWasOnMain.withLock { $0 } == false)
            #expect(heartbeat.name == "telemetry.heartbeat")
            #expect(Set(heartbeat.properties.keys) == [
                "app", "build", "version", "pending_batches", "dropped_events",
                "last_successful_upload", "transport"
            ])

            let sentinel = "PRIVATE_TRANSCRIPT_SENTINEL"
            adapter.track(TelemetryEvent(
                name: "product.user_action",
                properties: ["action": "settings_opened", "transcript": sentinel]
            ))
            #expect(adapter.diagnostics.rejectedEventCount == 1)
            #expect(fixture.persistedBytes().allSatisfy { $0.range(of: Data(sentinel.utf8)) == nil })

            coordinator.trackBlob(.userAction(.settingsOpened))
            await coordinator.flushBlob()

            let requests = BlobPublicBoundaryProtocol.requests
            #expect(requests.count == 1)
            let requestBytes = try requests.reduce(into: Data()) {
                $0.append(try gunzipBlobRequest($1.body))
            }
            #expect(requestBytes.range(of: Data(sentinel.utf8)) == nil)
            let events = try decodeBlobEvents(requestBytes)
            #expect(events.map(\.name) == ["telemetry.heartbeat", "product.user_action"])
            #expect(events.last?.properties == ["action": "settings_opened"])
        }

        @Test func publicAdapterFailureRetainsBytesAndRetryDeliversSameEvents() async throws {
            let fixture = try BlobPublicBoundaryFixture()
            defer { fixture.remove() }
            BlobPublicBoundaryProtocol.reset(mode: .hold)
            let service = try fixture.makeService()
            service.track(BlobProductTelemetryEvent.userAction(.fullPanelOpened).telemetryEvent)

            let failedFlush = Task { await service.flush() }
            await BlobPublicBoundaryProtocol.waitForRequest()
            let retainedAfterRequestEntered = fixture.persistedSnapshot()
            #expect(BlobPublicBoundaryProtocol.requests.count == 1)
            let failedRequest = try #require(BlobPublicBoundaryProtocol.requests.first)
            BlobPublicBoundaryProtocol.completeHeld(status: 503)
            await failedFlush.value

            #expect(service.diagnostics.lastError == .httpFailure(503))
            #expect(!retainedAfterRequestEntered.isEmpty)
            #expect(fixture.persistedSnapshot() == retainedAfterRequestEntered)
            let failedBody = try gunzipBlobRequest(failedRequest.body)

            BlobPublicBoundaryProtocol.setMode(.status(201))
            await service.flush()

            let requests = BlobPublicBoundaryProtocol.requests
            #expect(requests.count == 2)
            #expect(try gunzipBlobRequest(requests[1].body) == failedBody)
            #expect(service.diagnostics.lastSuccessfulUpload != nil)
            #expect(fixture.persistedSnapshot() != retainedAfterRequestEntered)
        }

        @Test func publicAdapterCancellationRetainsBytesUntilExplicitReenableRetry() async throws {
            let fixture = try BlobPublicBoundaryFixture()
            defer { fixture.remove() }
            BlobPublicBoundaryProtocol.reset(mode: .hold)
            let service = Mutex<AzureBlobTelemetryService?>(nil)
            let coordinator = TelemetryLifecycleCoordinator(isEnabled: false) { NoopTelemetryService() }
            let bootstrap = fixture.bootstrap {
                let adapter = try fixture.makeService()
                service.withLock { $0 = adapter }
                return adapter
            }
            #expect(await coordinator.bootstrapBlob(bootstrap) == .ready)
            coordinator.trackBlob(.userAction(.quickRecordStopped))

            let flush = Task { await coordinator.flushBlob() }
            await BlobPublicBoundaryProtocol.waitForRequest()
            let retainedAfterRequestEntered = fixture.persistedSnapshot()
            #expect(BlobPublicBoundaryProtocol.requests.count == 1)
            let cancelledRequest = try #require(BlobPublicBoundaryProtocol.requests.first)
            await coordinator.disableBlob()
            await flush.value

            let adapter = try #require(service.withLock { $0 })
            #expect(adapter.diagnostics.cancellationCount == 1)
            #expect(fixture.persistedSnapshot() == retainedAfterRequestEntered)

            BlobPublicBoundaryProtocol.setMode(.status(201))
            #expect(await coordinator.bootstrapBlob(bootstrap) == .ready)
            await coordinator.flushBlob()
            let requests = BlobPublicBoundaryProtocol.requests
            #expect(requests.count == 2)
            #expect(requests[1].url == cancelledRequest.url)
            #expect(requests[1].body == cancelledRequest.body)
            #expect(adapter.diagnostics.lastSuccessfulUpload != nil)
            #expect(fixture.persistedSnapshot() != retainedAfterRequestEntered)
        }
    }

    private struct BlobPublicBoundaryFixture {
        let root: URL
        let store: URL
        let bundle: Bundle
        let configuration: URLSessionConfiguration

        init(metadata: [String: String] = [
            "CFBundleName": "VoxPocket",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0"
        ]) throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "VoxPocketTests/blob-\(UUID().uuidString)", directoryHint: .isDirectory)
            store = root.appending(path: "store", directoryHint: .isDirectory)
            let bundleURL = root.appending(path: "Synthetic.bundle", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            var info = [
                "CFBundleIdentifier": "invalid.example.voxpocket.telemetry",
                "LokiKitBlobEndpoint": "https://blob.example.invalid/container",
                "LokiKitBlobSAS": "sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake"
            ]
            info.merge(metadata) { _, metadataValue in metadataValue }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: bundleURL.appending(path: "Info.plist"))
            bundle = try #require(Bundle(url: bundleURL))
            configuration = .ephemeral
            configuration.protocolClasses = [BlobPublicBoundaryProtocol.self]
        }

        func bootstrap(
            makeService: @escaping @Sendable () throws -> any TelemetryService
        ) -> BlobTelemetryBootstrap {
            BlobTelemetryBootstrap.testing(
                configuration: .enabled(.init(
                    endpoint: URL(string: "https://blob.example.invalid/container")!,
                    sasQuery: "sv=2023-11-03&sr=c&si=synthetic-create-only&spr=https&sig=fake"
                )),
                host: .interactiveApplication,
                isConsented: true,
                makeService: makeService
            )
        }

        func makeService() throws -> AzureBlobTelemetryService {
            try AzureBlobTelemetryService(
                bundle: bundle,
                app: "VoxPocket",
                build: "1",
                version: "1.0",
                privacy: BlobTelemetryMetadata(app: "VoxPocket", build: "1", version: "1.0").makePrivacyPolicy(),
                storeDirectory: store,
                isEnabled: true,
                identityProvider: { UUID(uuidString: "11111111-1111-4111-8111-111111111111")! },
                configuration: configuration
            )
        }

        func persistedBytes() -> [Data] {
            Array(persistedSnapshot().values)
        }

        func persistedSnapshot() -> [String: Data] {
            guard let enumerator = FileManager.default.enumerator(
                at: store,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else { return [:] }
            return enumerator.reduce(into: [:]) { result, element in
                guard let url = element as? URL,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                else { return }
                let relativePath = String(url.path.dropFirst(store.path.count + 1))
                result[relativePath] = try? Data(contentsOf: url)
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class BlobPublicBoundaryProtocol: URLProtocol {
        enum Mode: Sendable {
            case status(Int)
            case hold
        }

        private struct State {
            var mode: Mode = .status(201)
            var requests: [(url: URL, body: Data)] = []
            var waiters: [CheckedContinuation<Void, Never>] = []
        }
        private static let state = Mutex(State())
        private static let heldResponseNotification = Notification.Name(
            "BlobPublicBoundaryProtocol.heldResponse"
        )

        static var requests: [(url: URL, body: Data)] {
            state.withLock { $0.requests }
        }

        static func reset(mode: Mode) {
            state.withLock { $0 = State(mode: mode) }
        }

        static func setMode(_ mode: Mode) {
            state.withLock { $0.mode = mode }
        }

        static func completeHeld(status: Int) {
            NotificationCenter.default.post(
                name: heldResponseNotification,
                object: nil,
                userInfo: ["status": status]
            )
        }

        static func waitForRequest() async {
            await withCheckedContinuation { continuation in
                let alreadyReceived = state.withLock { state -> Bool in
                    guard state.requests.isEmpty else { return true }
                    state.waiters.append(continuation)
                    return false
                }
                if alreadyReceived { continuation.resume() }
            }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let body = readBlobRequestBody(request)
            let result = Self.state.withLock { state -> (Mode, [CheckedContinuation<Void, Never>]) in
                state.requests.append((request.url!, body))
                let waiters = state.waiters
                state.waiters.removeAll()
                return (state.mode, waiters)
            }
            if case .hold = result.0 {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(completeHeldResponse(_:)),
                    name: Self.heldResponseNotification,
                    object: nil
                )
            }
            result.1.forEach { $0.resume() }
            switch result.0 {
            case .status(let status):
                respond(status: status)
            case .hold:
                break
            }
        }

        override func stopLoading() {
            NotificationCenter.default.removeObserver(
                self,
                name: Self.heldResponseNotification,
                object: nil
            )
        }

        @objc private func completeHeldResponse(_ notification: Notification) {
            guard let status = notification.userInfo?["status"] as? Int else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: Self.heldResponseNotification,
                object: nil
            )
            respond(status: status)
        }

        private func respond(status: Int) {
            client?.urlProtocol(
                self,
                didReceive: HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func readBlobRequestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    private func gunzipBlobRequest(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw BlobTelemetryPolicyFailure.forbiddenValueClass
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var result = Data()
            var status = Z_OK
            while status == Z_OK {
                var buffer = [UInt8](repeating: 0, count: 4_096)
                status = buffer.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                result.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
            }
            guard status == Z_STREAM_END, stream.avail_in == 0 else {
                throw BlobTelemetryPolicyFailure.forbiddenValueClass
            }
            return result
        }
    }

    private func decodeBlobEvents(_ data: Data) throws -> [TelemetryEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 0x0a).map {
            try decoder.decode(TelemetryEvent.self, from: Data($0))
        }
    }

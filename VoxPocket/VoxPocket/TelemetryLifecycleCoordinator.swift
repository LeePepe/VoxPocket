import Dispatch
import Foundation
import LokiKit
import Synchronization

struct BlobTelemetryBootstrap: Sendable {
    fileprivate typealias ServiceFactory = @Sendable () throws -> any TelemetryService

    fileprivate let configuration: BlobTelemetryConfiguration
    fileprivate let host: BlobTelemetryHostKind
    fileprivate let isConsented: Bool
    fileprivate let makeService: ServiceFactory

    private init(
        configuration: BlobTelemetryConfiguration,
        host: BlobTelemetryHostKind,
        isConsented: Bool,
        makeService: @escaping ServiceFactory
    ) {
        self.configuration = configuration
        self.host = host
        self.isConsented = isConsented
        self.makeService = makeService
    }

    static func production(
        host: BlobTelemetryHostKind,
        isConsented: Bool,
        storeDirectory: URL,
        identityProvider: @escaping @Sendable () throws -> UUID
    ) -> Self {
        let bundle = Bundle.main
        let metadata = BlobTelemetryMetadata.trusted(from: bundle)
        return Self(
            configuration: BlobTelemetryConfiguration(),
            host: host,
            isConsented: isConsented,
            makeService: {
                guard let metadata else {
                    throw BlobTelemetryBootstrapConstructionFailure.invalidBundleMetadata
                }
                return try AzureBlobTelemetryService(
                    bundle: bundle,
                    app: metadata.app,
                    build: metadata.build,
                    version: metadata.version,
                    privacy: metadata.makePrivacyPolicy(),
                    storeDirectory: storeDirectory,
                    isEnabled: true,
                    identityProvider: identityProvider
                )
            }
        )
    }

    #if DEBUG
    static func testing(
        configuration: BlobTelemetryConfiguration,
        host: BlobTelemetryHostKind,
        isConsented: Bool,
        makeService: @escaping @Sendable () throws -> any TelemetryService
    ) -> Self {
        Self(
            configuration: configuration,
            host: host,
            isConsented: isConsented,
            makeService: makeService
        )
    }

    static func testingProduction(
        bundle: Bundle,
        host: BlobTelemetryHostKind,
        isConsented: Bool,
        storeDirectory: URL,
        identityProvider: @escaping @Sendable () throws -> UUID
    ) -> Self {
        let metadata = BlobTelemetryMetadata.trusted(from: bundle)
        return Self(
            configuration: BlobTelemetryConfiguration(testingBundle: bundle),
            host: host,
            isConsented: isConsented,
            makeService: {
                guard let metadata else {
                    throw BlobTelemetryBootstrapConstructionFailure.invalidBundleMetadata
                }
                return try AzureBlobTelemetryService(
                    bundle: bundle,
                    app: metadata.app,
                    build: metadata.build,
                    version: metadata.version,
                    privacy: metadata.makePrivacyPolicy(),
                    storeDirectory: storeDirectory,
                    isEnabled: true,
                    identityProvider: identityProvider
                )
            }
        )
    }

    func makeTestingService() throws -> any TelemetryService {
        try makeService()
    }
    #endif
}

private enum BlobTelemetryBootstrapConstructionFailure: Error {
    case invalidBundleMetadata
}

final class TelemetryLifecycleCoordinator: TelemetryService, Sendable {
    typealias ProviderFactory = @Sendable () -> any TelemetryService

    private let worker: TelemetryLifecycleWorker
    private let enabled: Mutex<Bool>

    var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set {
            enabled.withLock { $0 = newValue }
            worker.submit(.setEnabled(newValue))
        }
    }

    init(
        isEnabled: Bool = true,
        flushAdmissionObserver: @escaping @Sendable () -> Void = {},
        providerFactory: @escaping ProviderFactory
    ) {
        enabled = Mutex(isEnabled)
        worker = TelemetryLifecycleWorker(
            providerFactory: providerFactory,
            flushAdmissionObserver: flushAdmissionObserver
        )
    }

    func track(_ event: TelemetryEvent) {
        worker.submit(.track(event))
    }

    func track(name: String, properties: [String: String]) {
        track(TelemetryEvent(name: name, properties: properties))
    }

    func flush() async {
        await worker.flush()
    }

    func resetIdentifier() {
        worker.submit(.resetIdentifier)
    }

    func bootstrapBlob(_ bootstrap: BlobTelemetryBootstrap) async -> BlobTelemetryBootstrapOutcome {
        guard bootstrap.host.isEligibleForBlobTelemetry else { return .ineligibleHost }
        switch bootstrap.configuration {
        case .disabled:
            return .configurationDisabled
        case .invalid(let failure):
            return .invalidConfiguration(failure)
        case .enabled:
            break
        }
        guard bootstrap.isConsented else { return .consentRequired }
        return await worker.bootstrapBlob(bootstrap.makeService)
    }

    func trackBlob(_ event: BlobProductTelemetryEvent) {
        worker.submit(.trackBlob(event.telemetryEvent))
    }

    func flushBlob() async {
        await worker.flush(.blob)
    }

    func disableBlob() async {
        await worker.disableBlob()
    }
}

private final class TelemetryLifecycleWorker: Sendable {
    enum Operation: Sendable {
        case track(TelemetryEvent)
        case setEnabled(Bool)
        case resetIdentifier
        case bootstrapBlob(
            BlobTelemetryBootstrap.ServiceFactory,
            UInt64,
            CheckedContinuation<BlobTelemetryBootstrapOutcome, Never>
        )
        case trackBlob(TelemetryEvent)
        case disableBlob(CheckedContinuation<Void, Never>)
    }

    enum FlushKind: Sendable {
        case legacy
        case blob
    }

    private enum PendingAdmission: Sendable {
        case operation(Operation)
        case flush(FlushKind, [CheckedContinuation<Void, Never>])
    }

    private struct ActiveFlush: Sendable {
        let kind: FlushKind
        var waiters: [CheckedContinuation<Void, Never>]
    }

    private struct State: Sendable {
        var provider: (any TelemetryService)?
        var blobProvider: (any TelemetryService)?
        var blobDesiredEnabled = false
        var blobGeneration: UInt64 = 0
        var activeFlush: ActiveFlush?
        var pendingAdmissions: [PendingAdmission] = []
    }

    private let queue = DispatchQueue(
        label: "com.leepepe.voxpocket.telemetry-lifecycle",
        qos: .utility
    )
    private let providerFactory: TelemetryLifecycleCoordinator.ProviderFactory
    private let flushAdmissionObserver: @Sendable () -> Void
    private let state = Mutex(State())

    init(
        providerFactory: @escaping TelemetryLifecycleCoordinator.ProviderFactory,
        flushAdmissionObserver: @escaping @Sendable () -> Void
    ) {
        self.providerFactory = providerFactory
        self.flushAdmissionObserver = flushAdmissionObserver
    }

    func submit(_ operation: Operation) {
        queue.async { [self] in
            if case .disableBlob = operation {
                perform(operation)
                return
            }
            let isQueued = state.withLock { state in
                guard state.activeFlush != nil else { return false }
                state.pendingAdmissions.append(.operation(operation))
                return true
            }
            guard !isQueued else { return }
            perform(operation)
        }
    }

    func flush() async {
        await flush(.legacy)
    }

    func flush(_ kind: FlushKind) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let shouldStartFlush = state.withLock { state in
                    guard let activeFlush = state.activeFlush else {
                        state.activeFlush = ActiveFlush(kind: kind, waiters: [continuation])
                        return true
                    }

                    if state.pendingAdmissions.isEmpty, activeFlush.kind == kind {
                        state.activeFlush?.waiters.append(continuation)
                    } else if case .flush(let pendingKind, var waiters) = state.pendingAdmissions.last,
                              pendingKind == kind {
                        waiters.append(continuation)
                        state.pendingAdmissions[state.pendingAdmissions.count - 1] = .flush(kind, waiters)
                    } else {
                        state.pendingAdmissions.append(.flush(kind, [continuation]))
                    }
                    return false
                }
                flushAdmissionObserver()
                guard shouldStartFlush else { return }
                startFlush(kind)
            }
        }
    }

    func bootstrapBlob(
        _ factory: @escaping BlobTelemetryBootstrap.ServiceFactory
    ) async -> BlobTelemetryBootstrapOutcome {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let generation = state.withLock { state in
                    state.blobGeneration &+= 1
                    state.blobDesiredEnabled = true
                    return state.blobGeneration
                }
                submit(.bootstrapBlob(factory, generation, continuation))
            }
        }
    }

    func disableBlob() async {
        await withCheckedContinuation { continuation in
            submit(.disableBlob(continuation))
        }
    }

    private func provider() -> any TelemetryService {
        if let provider = state.withLock({ $0.provider }) {
            return provider
        }
        let provider = providerFactory()
        state.withLock { $0.provider = provider }
        return provider
    }

    private func perform(_ operation: Operation) {
        switch operation {
        case .track(let event):
            provider().track(event)
        case .setEnabled(let isEnabled):
            provider().isEnabled = isEnabled
        case .resetIdentifier:
            provider().resetIdentifier()
        case .bootstrapBlob(let factory, let generation, let continuation):
            guard isCurrentBlobGeneration(generation) else {
                continuation.resume(returning: .consentRequired)
                return
            }
            if let blobProvider = state.withLock({ $0.blobProvider }) {
                blobProvider.isEnabled = true
                continuation.resume(returning: .ready)
                return
            }
            do {
                let blobProvider = try factory()
                guard isCurrentBlobGeneration(generation) else {
                    blobProvider.isEnabled = false
                    continuation.resume(returning: .consentRequired)
                    return
                }
                state.withLock { $0.blobProvider = blobProvider }
                continuation.resume(returning: .ready)
            } catch {
                continuation.resume(returning: .constructionFailed)
            }
        case .trackBlob(let event):
            let blobProvider = state.withLock {
                $0.blobDesiredEnabled ? $0.blobProvider : nil
            }
            blobProvider?.track(event)
        case .disableBlob(let continuation):
            let blobProvider = state.withLock { state in
                state.blobGeneration &+= 1
                state.blobDesiredEnabled = false
                return state.blobProvider
            }
            blobProvider?.isEnabled = false
            continuation.resume()
        }
    }

    private func isCurrentBlobGeneration(_ generation: UInt64) -> Bool {
        state.withLock { $0.blobDesiredEnabled && $0.blobGeneration == generation }
    }

    private func startFlush(_ kind: FlushKind) {
        let selectedProvider: (any TelemetryService)? = switch kind {
        case .legacy:
            provider()
        case .blob:
            state.withLock { $0.blobDesiredEnabled ? $0.blobProvider : nil }
        }
        guard let selectedProvider else {
            completeFlush()
            return
        }
        Task.detached(priority: .utility) { [self] in
            await selectedProvider.flush()
            queue.async { [self] in completeFlush() }
        }
    }

    private func completeFlush() {
        let waiters = state.withLock { state in
            let waiters = state.activeFlush?.waiters ?? []
            state.activeFlush = nil
            return waiters
        }
        waiters.forEach { $0.resume() }
        processPendingAdmissions()
    }

    private func processPendingAdmissions() {
        while let admission = state.withLock({ state in
            state.pendingAdmissions.isEmpty ? nil : state.pendingAdmissions.removeFirst()
        }) {
            switch admission {
            case .operation(let operation):
                perform(operation)
            case .flush(let kind, let waiters):
                state.withLock { $0.activeFlush = ActiveFlush(kind: kind, waiters: waiters) }
                startFlush(kind)
                return
            }
        }
    }
}

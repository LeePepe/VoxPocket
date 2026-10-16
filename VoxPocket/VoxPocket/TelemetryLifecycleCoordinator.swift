import Dispatch
import LokiKit
import Synchronization

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
        providerFactory: @escaping ProviderFactory
    ) {
        enabled = Mutex(isEnabled)
        worker = TelemetryLifecycleWorker(providerFactory: providerFactory)
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
}

private final class TelemetryLifecycleWorker: Sendable {
    enum Operation: Sendable {
        case track(TelemetryEvent)
        case setEnabled(Bool)
        case resetIdentifier
    }

    private enum PendingAdmission: Sendable {
        case operation(Operation)
        case flush([CheckedContinuation<Void, Never>])
    }

    private struct State: Sendable {
        var provider: (any TelemetryService)?
        var activeFlushWaiters: [CheckedContinuation<Void, Never>]?
        var pendingAdmissions: [PendingAdmission] = []
    }

    private let queue = DispatchQueue(
        label: "com.leepepe.voxpocket.telemetry-lifecycle",
        qos: .utility
    )
    private let providerFactory: TelemetryLifecycleCoordinator.ProviderFactory
    private let state = Mutex(State())

    init(providerFactory: @escaping TelemetryLifecycleCoordinator.ProviderFactory) {
        self.providerFactory = providerFactory
    }

    func submit(_ operation: Operation) {
        queue.async { [self] in
            let isQueued = state.withLock { state in
                guard state.activeFlushWaiters != nil else { return false }
                state.pendingAdmissions.append(.operation(operation))
                return true
            }
            guard !isQueued else { return }
            perform(operation, provider: provider())
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let shouldStartFlush = state.withLock { state in
                    guard state.activeFlushWaiters != nil else {
                        state.activeFlushWaiters = [continuation]
                        return true
                    }

                    if state.pendingAdmissions.isEmpty {
                        state.activeFlushWaiters?.append(continuation)
                    } else if case .flush(var waiters) = state.pendingAdmissions.last {
                        waiters.append(continuation)
                        state.pendingAdmissions[state.pendingAdmissions.count - 1] = .flush(waiters)
                    } else {
                        state.pendingAdmissions.append(.flush([continuation]))
                    }
                    return false
                }
                guard shouldStartFlush else { return }
                startFlush()
            }
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

    private func perform(
        _ operation: Operation,
        provider: any TelemetryService
    ) {
        switch operation {
        case .track(let event):
            provider.track(event)
        case .setEnabled(let isEnabled):
            provider.isEnabled = isEnabled
        case .resetIdentifier:
            provider.resetIdentifier()
        }
    }

    private func startFlush() {
        let provider = provider()
        Task.detached(priority: .utility) { [self] in
            await provider.flush()
            queue.async { [self] in completeFlush() }
        }
    }

    private func completeFlush() {
        let waiters = state.withLock { state in
            let waiters = state.activeFlushWaiters ?? []
            state.activeFlushWaiters = nil
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
                perform(operation, provider: provider())
            case .flush(let waiters):
                state.withLock { $0.activeFlushWaiters = waiters }
                startFlush()
                return
            }
        }
    }
}

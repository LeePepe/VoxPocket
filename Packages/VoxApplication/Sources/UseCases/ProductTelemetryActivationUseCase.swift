import Foundation

public struct ProductTelemetryActivationDependencies: Sendable {
    public typealias ConsentReader = @MainActor @Sendable () async -> Bool
    public typealias ConsentWriter = @MainActor @Sendable (Bool) async -> Void
    public typealias IdentityInstaller = @MainActor @Sendable () async -> UUID?
    public typealias Activator = @MainActor @Sendable (UUID) async -> Bool
    public typealias Deactivator = @MainActor @Sendable () async -> Void

    let readConsent: ConsentReader
    let persistConsent: ConsentWriter
    let installIdentityIfConsented: IdentityInstaller
    let activate: Activator
    let deactivate: Deactivator

    public init(
        readConsent: @escaping ConsentReader,
        persistConsent: @escaping ConsentWriter,
        installIdentityIfConsented: @escaping IdentityInstaller,
        activate: @escaping Activator,
        deactivate: @escaping Deactivator
    ) {
        self.readConsent = readConsent
        self.persistConsent = persistConsent
        self.installIdentityIfConsented = installIdentityIfConsented
        self.activate = activate
        self.deactivate = deactivate
    }
}

@MainActor
public protocol ProductTelemetryActivationUseCase: AnyObject {
    var isReady: Bool { get }

    @discardableResult
    func beginConsentTransition(
        _ isConsented: Bool,
        isEligible: Bool
    ) -> Task<Void, Never>
    func activateAtStartupIfEligible(_ isEligible: Bool) async
    func waitForPendingTransition() async
}

@MainActor
public final class DefaultProductTelemetryActivationUseCase: ProductTelemetryActivationUseCase {
    #if DEBUG
    public typealias ActivationCheckpoint = @MainActor @Sendable () async -> Void
    typealias PendingTransitionAwaiter = @MainActor @Sendable (Task<Void, Never>?) async -> Void
    #endif

    private let dependencies: ProductTelemetryActivationDependencies
    #if DEBUG
    private let activationCheckpoint: ActivationCheckpoint
    private let pendingTransitionAwaiter: PendingTransitionAwaiter
    #endif
    public private(set) var isReady = false
    private var consentIntentGeneration: UInt64 = 0
    private var pendingTransition: Task<Void, Never>?

    public init(dependencies: ProductTelemetryActivationDependencies) {
        self.dependencies = dependencies
        #if DEBUG
        activationCheckpoint = {}
        pendingTransitionAwaiter = { capturedTask in
            await capturedTask?.value
        }
        #endif
    }

    #if DEBUG
    public init(
        dependencies: ProductTelemetryActivationDependencies,
        activationCheckpoint: @escaping ActivationCheckpoint
    ) {
        self.dependencies = dependencies
        self.activationCheckpoint = activationCheckpoint
        pendingTransitionAwaiter = { capturedTask in
            await capturedTask?.value
        }
    }

    init(
        dependencies: ProductTelemetryActivationDependencies,
        activationCheckpoint: @escaping ActivationCheckpoint,
        pendingTransitionAwaiter: @escaping PendingTransitionAwaiter
    ) {
        self.dependencies = dependencies
        self.activationCheckpoint = activationCheckpoint
        self.pendingTransitionAwaiter = pendingTransitionAwaiter
    }
    #endif

    @discardableResult
    public func beginConsentTransition(
        _ isConsented: Bool,
        isEligible: Bool
    ) -> Task<Void, Never> {
        let prior = pendingTransition
        prior?.cancel()
        consentIntentGeneration &+= 1
        let currentIntent = consentIntentGeneration
        isReady = false
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if !isConsented {
                await dependencies.deactivate()
                await prior?.value
                guard isCurrentIntent(currentIntent) else { return }
                await dependencies.persistConsent(false)
                return
            }
            await prior?.value
            guard isCurrentIntent(currentIntent) else { return }
            await dependencies.persistConsent(true)
            guard isCurrentIntent(currentIntent) else { return }
            await activateIfEligible(isEligible, intent: currentIntent)
        }
        pendingTransition = task
        return task
    }

    public func waitForPendingTransition() async {
        while true {
            let intent = consentIntentGeneration
            await pendingTransition?.value
            guard intent == consentIntentGeneration else { continue }
            return
        }
    }

    public func activateAtStartupIfEligible(_ isEligible: Bool) async {
        while true {
            let observedIntent = consentIntentGeneration
            let explicitTransition = pendingTransition
            #if DEBUG
            await pendingTransitionAwaiter(explicitTransition)
            #else
            await explicitTransition?.value
            #endif
            guard observedIntent == consentIntentGeneration else { continue }
            await activateIfEligible(isEligible, intent: observedIntent)
            return
        }
    }

    private func activateIfEligible(_ isEligible: Bool, intent: UInt64) async {
        guard isCurrentIntent(intent), isEligible else { return }
        guard await dependencies.readConsent() else { return }
        guard isCurrentIntent(intent) else { return }
        guard let identity = await dependencies.installIdentityIfConsented() else { return }
        guard isCurrentIntent(intent) else { return }
        let activated = await dependencies.activate(identity)
        #if DEBUG
        await activationCheckpoint()
        #endif
        guard isCurrentIntent(intent) else { return }
        isReady = activated
    }

    private func isCurrentIntent(_ intent: UInt64) -> Bool {
        !Task.isCancelled && consentIntentGeneration == intent
    }
}

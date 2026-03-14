import Foundation
import Combine
import TranscriptionKit
import CoreModels

/// 录音用例默认实现
///
/// 桥接 `TranscriptionCoordinator` 到 `RecordingUseCase` 协议。
public final class DefaultRecordingUseCase: RecordingUseCase, @unchecked Sendable {

    private let primaryCoordinator: TranscriptionCoordinator
    private let fallbackCoordinator: (any TranscriptionCoordinator)?
    private let operationGate = RecordingOperationGate()
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0)
    private var cancellables = Set<AnyCancellable>()
    private var language: Locale
    private let activeSelectionLock = NSLock()
    private var activeSelection: ActiveSelection = .primary

    public var state: RecordingState { stateSubject.value }

    public var statePublisher: AnyPublisher<RecordingState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    public init(
        coordinator: TranscriptionCoordinator,
        fallbackCoordinator: (any TranscriptionCoordinator)? = nil,
        language: Locale = Locale(identifier: "zh-Hans")
    ) {
        self.primaryCoordinator = coordinator
        self.fallbackCoordinator = fallbackCoordinator
        self.language = language

        bindCoordinatorPublishers(coordinator, selection: .primary)
        if let fallbackCoordinator {
            bindCoordinatorPublishers(fallbackCoordinator, selection: .fallback)
        }
    }

    public func startRecording() async throws {
        let coordinator = try resolveCoordinatorForStart()
        let language = self.language
        try await operationGate.withExclusiveAccess { [weak self] in
            guard let self else { return }
            self.setActiveSelection(self.selection(for: coordinator))
            try await coordinator.start(language: language)
        }
    }

    public func stopRecording() async throws {
        let coordinator = currentCoordinator()
        await operationGate.withExclusiveAccess {
            await coordinator.stop()
        }
    }

    public func pauseRecording() {
        currentCoordinator().pause()
    }

    public func resumeRecording() {
        currentCoordinator().resume()
    }

    public func cancelRecording() {
        Task { [weak self] in
            guard let self else { return }
            let coordinator = self.currentCoordinator()
            await self.operationGate.withExclusiveAccess {
                await coordinator.stop()
            }
            self.stateSubject.send(.idle)
            self.audioLevelSubject.send(0)
        }
    }

    public func checkPermission() async -> Bool {
        currentCoordinator().audioCaptureService.hasPermission
    }

    public func requestPermission() async -> Bool {
        await currentCoordinator().audioCaptureService.requestPermission()
    }

    private func bindCoordinatorPublishers(
        _ coordinator: any TranscriptionCoordinator,
        selection: ActiveSelection
    ) {
        coordinator.audioCaptureService.statePublisher
            .sink { [weak self] captureState in
                guard let self, self.currentSelection() == selection else { return }
                switch captureState {
                case .idle:
                    self.stateSubject.send(.idle)
                    self.audioLevelSubject.send(0)
                    self.setActiveSelection(.primary)
                case .recording:
                    self.stateSubject.send(.recording(duration: 0))
                case .paused:
                    self.stateSubject.send(.paused(duration: 0))
                case .error(let message):
                    self.stateSubject.send(.error(message))
                }
            }
            .store(in: &cancellables)

        coordinator.audioLevelPublisher
            .sink { [weak self] level in
                guard let self, self.currentSelection() == selection else { return }
                self.audioLevelSubject.send(level)
            }
            .store(in: &cancellables)
    }

    private func resolveCoordinatorForStart() throws -> any TranscriptionCoordinator {
        guard let loadable = primaryCoordinator as? any ModelLoadingObservable else {
            return primaryCoordinator
        }

        switch loadable.modelLoadingState {
        case .ready:
            return primaryCoordinator
        case .downloading, .loading, .idle, .failed:
            if let fallbackCoordinator {
                return fallbackCoordinator
            }
        }

        switch loadable.modelLoadingState {
        case .ready:
            return primaryCoordinator
        case .downloading(let progress):
            let percent = Int(progress * 100)
            throw VoxError.transcriptionFailed(reason: "本地模型正在下载（\(percent)%）")
        case .loading:
            throw VoxError.transcriptionFailed(reason: "本地模型正在初始化，请稍候再试")
        case .failed(let reason):
            throw VoxError.transcriptionFailed(reason: "本地模型加载失败：\(reason)")
        case .idle:
            throw VoxError.modelNotReady
        }
    }

    private func currentCoordinator() -> any TranscriptionCoordinator {
        switch currentSelection() {
        case .primary:
            return primaryCoordinator
        case .fallback:
            return fallbackCoordinator ?? primaryCoordinator
        }
    }

    private func selection(for coordinator: any TranscriptionCoordinator) -> ActiveSelection {
        if let fallbackCoordinator,
           ObjectIdentifier(fallbackCoordinator) == ObjectIdentifier(coordinator) {
            return .fallback
        }
        return .primary
    }

    private func currentSelection() -> ActiveSelection {
        activeSelectionLock.lock()
        defer { activeSelectionLock.unlock() }
        return activeSelection
    }

    private func setActiveSelection(_ selection: ActiveSelection) {
        activeSelectionLock.lock()
        activeSelection = selection
        activeSelectionLock.unlock()
    }
}

private enum ActiveSelection {
    case primary
    case fallback
}

private actor RecordingOperationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withExclusiveAccess<T>(_ operation: () async throws -> T) async rethrows -> T {
        await lock()
        defer { unlock() }
        return try await operation()
    }

    private func lock() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func unlock() {
        if waiters.isEmpty {
            isLocked = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}

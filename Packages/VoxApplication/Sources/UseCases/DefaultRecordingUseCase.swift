import Foundation
import Combine
import TranscriptionKit

/// 录音用例默认实现
///
/// 桥接 `TranscriptionCoordinator` 到 `RecordingUseCase` 协议。
public final class DefaultRecordingUseCase: RecordingUseCase, @unchecked Sendable {

    private let coordinator: TranscriptionCoordinator
    private let stateSubject = CurrentValueSubject<RecordingState, Never>(.idle)
    private var cancellables = Set<AnyCancellable>()
    private var language: Locale

    public var state: RecordingState { stateSubject.value }

    public var statePublisher: AnyPublisher<RecordingState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public var audioLevelPublisher: AnyPublisher<Float, Never> {
        coordinator.audioLevelPublisher
    }

    public init(coordinator: TranscriptionCoordinator, language: Locale = Locale(identifier: "zh-Hans")) {
        self.coordinator = coordinator
        self.language = language

        // 监听 coordinator 的 audio capture 状态
        coordinator.audioCaptureService.statePublisher
            .sink { [weak self] captureState in
                guard let self else { return }
                switch captureState {
                case .idle:
                    self.stateSubject.send(.idle)
                case .recording:
                    self.stateSubject.send(.recording(duration: 0))
                case .paused:
                    self.stateSubject.send(.paused(duration: 0))
                case .error(let message):
                    self.stateSubject.send(.error(message))
                }
            }
            .store(in: &cancellables)
    }

    public func startRecording() async throws {
        // 移除手动状态更新，让监听器（line 30-44）自动处理
        // 避免状态更新竞态条件
        try await coordinator.start(language: language)
    }

    public func stopRecording() async throws {
        // 移除手动状态更新，让监听器（line 30-44）自动处理
        // 确保状态更新来源唯一，避免双重更新导致的竞态条件
        await coordinator.stop()
    }

    public func pauseRecording() {
        coordinator.pause()
    }

    public func resumeRecording() {
        coordinator.resume()
    }

    public func cancelRecording() {
        Task {
            await coordinator.stop()
        }
        stateSubject.send(.idle)
    }

    public func checkPermission() async -> Bool {
        coordinator.audioCaptureService.hasPermission
    }

    public func requestPermission() async -> Bool {
        await coordinator.audioCaptureService.requestPermission()
    }
}

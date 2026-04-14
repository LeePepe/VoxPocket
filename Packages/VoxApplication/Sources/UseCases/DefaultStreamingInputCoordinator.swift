import Foundation
import Combine
import Synchronization
import Observability

/// 流式输入协调器默认实现
///
/// 数据流：snapshotPublisher → scheduleRefinement → refineText → replaceVoiceZone
///
/// 安全不变量：
/// 1. 快照门控关闭先于订阅取消（防止晚到的最终结果静默丢失）
/// 2. isStreaming 原子性 check-and-set（防止并发双重启动）
/// 3. 每次 scheduleRefinement 先调用 refinementUseCase.cancel()（无幽灵 LLM 流）
/// 4. Generation ID + Task.isCancelled 双重保护每次写入（防止过期写入）
/// 5. simulatePaste 仅在 stopStreaming() 完成后由调用方触发
public final class DefaultStreamingInputCoordinator: @unchecked Sendable {

    // MARK: - 依赖

    private let editingUseCase: EditingUseCase
    private let transcriptionUseCase: TranscriptionUseCase
    private let refinementUseCase: RefinementUseCase
    private let logger: Logger

    // MARK: - 状态

    private struct CoordinatorState: @unchecked Sendable {
        var currentSnapshotText: String = ""
        var currentGeneration: UInt64 = 0
        var isStreaming: Bool = false
        var currentTask: Task<Void, Never>? = nil
        var lastRefinedText: String = ""
        var chunkCancellable: AnyCancellable? = nil
    }

    private let state = Mutex<CoordinatorState>(CoordinatorState())

    // MARK: - 输出

    private let refinedVoiceTextSubject = PassthroughSubject<String, Never>()

    public var refinedVoiceTextPublisher: AnyPublisher<String, Never> {
        refinedVoiceTextSubject.eraseToAnyPublisher()
    }

    // MARK: - Init

    public init(
        editing: EditingUseCase,
        transcription: TranscriptionUseCase,
        refinement: RefinementUseCase,
        logger: Logger? = nil
    ) {
        self.editingUseCase = editing
        self.transcriptionUseCase = transcription
        self.refinementUseCase = refinement
        self.logger = logger ?? PrintLogger(subsystem: "StreamingInputCoordinator")
    }
}

// MARK: - StreamingInputCoordinator

extension DefaultStreamingInputCoordinator: StreamingInputCoordinator {

    public func startStreaming() async {
        // 原子性 check-and-set：单锁区防止并发双重启动
        let shouldStart = state.withLock { s -> Bool in
            if s.isStreaming { return false }
            s.isStreaming = true
            s.currentSnapshotText = ""
            s.currentGeneration = 0
            s.lastRefinedText = ""
            return true
        }
        guard shouldStart else {
            logger.debug("startStreaming: already streaming, ignoring")
            return
        }

        // 设置语音锚点并锁定语音区域
        editingUseCase.setVoiceAnchor(editingUseCase.currentText.count)
        editingUseCase.setVoiceZoneLocked(true)
        logger.debug("startStreaming: voice anchor set at \(editingUseCase.currentText.count), zone locked")

        // 先订阅（PassthroughSubject：订阅后才能收到事件）
        let cancellable = transcriptionUseCase.snapshotPublisher
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.state.withLock { $0.currentSnapshotText = snapshot }
                self.scheduleRefinement(snapshot: snapshot)
            }
        state.withLock { $0.chunkCancellable = cancellable }

        // 订阅安装完成后再激活门控（不会漏掉快照）
        transcriptionUseCase.snapshotGateActive = true
        logger.debug("startStreaming: snapshot gate activated")
    }

    public func stopStreaming() async {
        // 1. 关闭门控（先于取消订阅，让晚到的最终结果路由到旧路径并记录错误）
        transcriptionUseCase.snapshotGateActive = false
        logger.debug("stopStreaming: snapshot gate closed")

        // 2. 原子性：取消订阅 + 使当前精炼失效
        let taskToAwait: Task<Void, Never>? = state.withLock { s in
            s.chunkCancellable?.cancel()
            s.chunkCancellable = nil
            s.currentGeneration &+= 1  // 使所有进行中的精炼失效
            let t = s.currentTask
            s.currentTask = nil
            return t
        }
        taskToAwait?.cancel()
        refinementUseCase.cancel()
        logger.debug("stopStreaming: subscription cancelled, in-flight refinement invalidated")

        // 3. 等待最后一次精炼完成，最多 5 秒
        if let task = taskToAwait {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await task.value }
                group.addTask {
                    try? await Task.sleep(for: .seconds(5))
                    task.cancel()
                }
                _ = await group.next()
                group.cancelAll()
            }
        }

        // 4. 解锁语音区域（defer 保证始终执行）
        defer {
            editingUseCase.setVoiceZoneLocked(false)
            editingUseCase.clearVoiceAnchor()
            state.withLock { $0.isStreaming = false }
            logger.debug("stopStreaming: voice zone unlocked, isStreaming = false")
        }

        // 5. 发布最终文本
        let finalText = state.withLock { s in
            s.lastRefinedText.isEmpty ? s.currentSnapshotText : s.lastRefinedText
        }
        if !finalText.isEmpty {
            await MainActor.run { self.refinedVoiceTextSubject.send(finalText) }
        }
        logger.debug("stopStreaming: final text emitted, length=\(finalText.count)")
    }

    public func cancel() {
        transcriptionUseCase.snapshotGateActive = false
        state.withLock { s in
            s.chunkCancellable?.cancel()
            s.chunkCancellable = nil
            s.currentGeneration &+= 1
            s.currentTask?.cancel()
            s.currentTask = nil
            s.currentSnapshotText = ""
            s.lastRefinedText = ""
            s.isStreaming = false
        }
        refinementUseCase.cancel()
        editingUseCase.clearVoiceAnchor()
        editingUseCase.setVoiceZoneLocked(false)
        logger.debug("cancel: streaming cancelled, voice zone unlocked")
    }
}

// MARK: - 私有方法

private extension DefaultStreamingInputCoordinator {

    /// 调度精炼任务（取消上一次后立即启动新任务）
    func scheduleRefinement(snapshot: String) {
        let gen: UInt64 = state.withLock { s in
            s.currentGeneration &+= 1
            s.currentTask?.cancel()
            s.currentTask = nil
            return s.currentGeneration
        }
        refinementUseCase.cancel()  // 终止上一次 LLM 流
        logger.debug("scheduleRefinement: gen=\(gen), snapshot length=\(snapshot.count)")

        let task = Task { [weak self, gen] in
            guard let self else { return }
            do {
                for try await event in self.refinementUseCase.refineText(snapshot, customPrompt: nil) {
                    guard self.state.withLock({ $0.currentGeneration }) == gen,
                          !Task.isCancelled else { return }
                    if case .chunk(let text) = event {
                        do {
                            try self.editingUseCase.replaceVoiceZone(with: text)
                        } catch {
                            self.logger.error("replaceVoiceZone failed: \(error.localizedDescription)")
                            return
                        }
                        self.state.withLock { $0.lastRefinedText = text }
                        await MainActor.run { self.refinedVoiceTextSubject.send(text) }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.logger.error("refineText stream error (gen=\(gen)): \(error.localizedDescription)")
                }
            }
        }
        state.withLock { $0.currentTask = task }
    }
}

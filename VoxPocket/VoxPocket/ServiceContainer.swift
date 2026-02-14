//
//  ServiceContainer.swift
//  VoxPocket
//
//  依赖注入容器，管理所有共享服务和用例实例
//

#if os(macOS)
import Foundation
import SwiftUI
import SwiftData
import Combine
import TranscriptionKit
import LLMKit
import UseCases
import CoreModels
import Persistence
import PlatformAdapters
import UIShared
import PlatformUI

/// 服务容器
///
/// 集中管理所有服务和用例实例，避免重复创建。
/// 提供工厂方法创建 ViewModel。
@MainActor
public final class ServiceContainer: ObservableObject {

    // MARK: - 单例

    public static let shared = ServiceContainer()

    // MARK: - 基础服务

    public let transcriber: AppleSpeechTranscriber
    public let llmService: DefaultLLMService
    public let clipboardService: MacOSClipboardService
    public let accessibilityService: MacOSAccessibilityService
    public let hotkeyService: MacOSGlobalHotkeyService

    // MARK: - Use Cases

    public let editingUseCase: DefaultEditingUseCase
    public let recordingUseCase: DefaultRecordingUseCase
    public let transcriptionUseCase: DefaultTranscriptionUseCase
    public let historyUseCase: DefaultHistoryUseCase
    public let refinementUseCase: DefaultRefinementUseCase

    /// 会话用例代理（启动时用内存实现，UI 就绪后延迟切换到 SwiftData）
    public let sessionUseCase: ProxySessionUseCase

    // MARK: - 状态跟踪

    /// 当前是否有录音正在进行
    @Published public var isRecordingActive: Bool = false

    /// 活动的录音源标识
    @Published public var activeRecordingSource: RecordingSource? = nil

    // MARK: - 初始化

    private init() {
        // 初始化基础服务
        transcriber = AppleSpeechTranscriber()
        llmService = DefaultLLMService()
        clipboardService = MacOSClipboardService.shared
        accessibilityService = MacOSAccessibilityService.shared
        hotkeyService = MacOSGlobalHotkeyService.shared

        // 初始化 Use Cases
        editingUseCase = DefaultEditingUseCase()
        recordingUseCase = DefaultRecordingUseCase(coordinator: transcriber)
        transcriptionUseCase = DefaultTranscriptionUseCase(coordinator: transcriber, editing: editingUseCase)
        historyUseCase = DefaultHistoryUseCase(editing: editingUseCase)
        refinementUseCase = DefaultRefinementUseCase(llmService: llmService, editing: editingUseCase)

        // 启动时先用内存实现，避免 ModelContainer 创建阻塞 UI
        sessionUseCase = ProxySessionUseCase(backing: InMemorySessionUseCase())

        print("✅ [ServiceContainer] Initialized")
    }

    // MARK: - 延迟持久化初始化

    /// 延迟初始化 SwiftData 持久化层
    ///
    /// 在 UI 首次渲染后调用，避免 ModelContainer 创建阻塞 App 初始化导致 UI 卡死。
    public func initializePersistence() {
        let schema = Schema([SessionRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let repository = SwiftDataSessionRepository(container: container)
            let swiftDataUseCase = DefaultSessionUseCase(repository: repository)
            sessionUseCase.switchBacking(to: swiftDataUseCase)
            print("✅ [ServiceContainer] SwiftData persistence initialized")
        } catch {
            print("❌ [ServiceContainer] Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - ViewModel 工厂方法

    /// 创建完整面板的 EditorViewModel
    public func makeEditorViewModel() -> EditorViewModel {
#if os(macOS)
        let clipboard: ClipboardService? = MacOSClipboardService.shared
#else
        let clipboard: ClipboardService? = nil
#endif
        return EditorViewModel(
            recording: recordingUseCase,
            transcription: transcriptionUseCase,
            editing: editingUseCase,
            history: historyUseCase,
            refinement: refinementUseCase,
            clipboard: clipboard,
            session: sessionUseCase
        )
    }

    /// 创建完整面板的 RootViewModel
    public func makeRootViewModel() -> RootViewModel<SessionListViewModel, EditorViewModel> {
        let editor = makeEditorViewModel()
        let sessionList = SessionListViewModel(sessionUseCase: sessionUseCase)
        return RootViewModel(sessionListState: sessionList, editorState: editor)
    }

    /// 创建快速录音的 ViewModel
    public func makeQuickRecordingViewModel() -> QuickRecordingViewModel {
        QuickRecordingViewModel(
            recordingUseCase: recordingUseCase,
            transcriptionUseCase: transcriptionUseCase,
            refinementUseCase: refinementUseCase,
            clipboardService: clipboardService
        )
    }

    // MARK: - 录音状态管理

    /// 尝试开始录音
    /// - Parameter source: 录音来源
    /// - Returns: 是否成功开始
    public func tryStartRecording(source: RecordingSource) -> Bool {
        guard !isRecordingActive else {
            print("⚠️ [ServiceContainer] Recording already active from: \(activeRecordingSource?.rawValue ?? "unknown")")
            return false
        }

        isRecordingActive = true
        activeRecordingSource = source
        print("🎙️ [ServiceContainer] Recording started from: \(source.rawValue)")
        return true
    }

    /// 结束录音
    public func endRecording() {
        isRecordingActive = false
        activeRecordingSource = nil
        print("⏹️ [ServiceContainer] Recording ended")
    }
}

// MARK: - 录音来源

public enum RecordingSource: String {
    case fullPanel = "FullPanel"
    case quickRecording = "QuickRecording"
    case mainWindow = "MainWindow"
}

// MARK: - 会话用例代理

/// 可热切换底层实现的 SessionUseCase 代理
///
/// 启动时使用 InMemorySessionUseCase，UI 就绪后切换到 SwiftData 实现。
/// 所有 ViewModel 持有此代理的引用，切换时自动生效。
public final class ProxySessionUseCase: SessionUseCase, @unchecked Sendable {

    private var backing: SessionUseCase
    private var sessionsSubscription: AnyCancellable?
    private let sessionsRelay = CurrentValueSubject<[Session], Error>([])

    init(backing: SessionUseCase) {
        self.backing = backing
        rebindPublisher()
    }

    /// 切换底层实现并重新加载数据
    func switchBacking(to newBacking: SessionUseCase) {
        backing = newBacking
        rebindPublisher()
        // 触发重新加载
        Task {
            _ = try? await fetchAllSessions()
        }
    }

    private func rebindPublisher() {
        sessionsSubscription = backing.sessionsPublisher
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.sessionsRelay.send(completion: completion)
                },
                receiveValue: { [weak self] sessions in
                    self?.sessionsRelay.send(sessions)
                }
            )
    }

    // MARK: - SessionUseCase 转发

    public var currentSession: Session? { backing.currentSession }

    public var currentSessionPublisher: AnyPublisher<Session?, Never> {
        backing.currentSessionPublisher
    }

    public var sessionsPublisher: AnyPublisher<[Session], Error> {
        sessionsRelay.eraseToAnyPublisher()
    }

    public func createSession(title: String?) async throws -> Session {
        try await backing.createSession(title: title)
    }

    public func loadSession(_ id: UUID) async throws {
        try await backing.loadSession(id)
    }

    public func saveCurrentSession() async throws {
        try await backing.saveCurrentSession()
    }

    public func fetchAllSessions() async throws -> [Session] {
        try await backing.fetchAllSessions()
    }

    public func deleteSession(_ id: UUID) async throws {
        try await backing.deleteSession(id)
    }

    public func updateSessionTitle(_ id: UUID, title: String) async throws {
        try await backing.updateSessionTitle(id, title: title)
    }

    public func closeCurrentSession() async throws {
        try await backing.closeCurrentSession()
    }

    @discardableResult
    public func saveCompletedSession(title: String?, rawText: String, refinedText: String) async throws -> Session {
        try await backing.saveCompletedSession(title: title, rawText: rawText, refinedText: refinedText)
    }
}
#endif

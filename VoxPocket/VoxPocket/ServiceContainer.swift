//
//  ServiceContainer.swift
//  VoxPocket
//
//  依赖注入容器，管理所有共享服务和用例实例
//

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
import Preferences
import UIShared
import Observability
#if os(macOS)
import PlatformUI
#endif

/// 服务容器
///
/// 集中管理所有服务和用例实例，避免重复创建。
/// 提供工厂方法创建 ViewModel。
@MainActor
public final class ServiceContainer: ObservableObject {
    private let preferencesStore = UserDefaultsPreferencesStore.shared
    private let logger: Logger

    // MARK: - 单例

    public static let shared = ServiceContainer()

    // MARK: - 基础服务

    /// 主转录器：默认使用 WhisperKit 本地模型，可按配置切换到其他实现
    public let transcriber: any TranscriptionCoordinator
    public let localModelLoadingObservable: (any ModelLoadingObservable)?
    public let llmService: DefaultLLMService

    // MARK: - Use Cases

    public let editingUseCase: DefaultEditingUseCase
    public let recordingUseCase: DefaultRecordingUseCase
    public let transcriptionUseCase: DefaultTranscriptionUseCase
    public let historyUseCase: DefaultHistoryUseCase
    public let refinementUseCase: DefaultRefinementUseCase

    /// 会话用例代理（启动时用内存实现，UI 就绪后延迟切换到 SwiftData）
    public let sessionUseCase: ProxySessionUseCase

    /// Deep Link 路由
    public let deepLinkRouter: DefaultDeepLinkRouter

#if os(macOS)
    public let clipboardService: MacOSClipboardService
    public let accessibilityService: MacOSAccessibilityService
    public let hotkeyService: MacOSGlobalHotkeyService
    public let claudeInboxService: MacOSClaudeInboxService

    // MARK: - Quick Recording 独立服务栈

    /// 快速录音专用转录器（空闲时轻量，同一时刻只有一个可以录音）
    public let quickTranscriber: any TranscriptionCoordinator
    public let quickEditingUseCase: DefaultEditingUseCase
    public let quickRecordingUseCase: DefaultRecordingUseCase
    public let quickTranscriptionUseCase: DefaultTranscriptionUseCase
    public let quickRefinementUseCase: DefaultRefinementUseCase
#endif

    // MARK: - 遥测

    public let telemetryService: any TelemetryService

    // MARK: - 状态跟踪

    /// 当前是否有录音正在进行
    @Published public var isRecordingActive: Bool = false

    /// 活动的录音源标识
    @Published public var activeRecordingSource: RecordingSource? = nil

    // MARK: - 初始化

    private init() {
        logger = PrintLogger(subsystem: "ServiceContainer")
        telemetryService = Self.makeTelemetryService()
        let azureConfig = Self.makeAzureFoundryConfig()

        // 初始化基础服务（按 LLMAppConfig.defaultTranscriberProvider 选择转录器）
        switch LLMAppConfig.defaultTranscriberProvider {
        case .localWhisperKit:
            let whisper = Self.makeLocalWhisperTranscriber(preloadOnStart: true)
            transcriber = LoadingFallbackTranscriptionCoordinator(
                primary: whisper,
                fallback: AppleSpeechTranscriber()
            )
            localModelLoadingObservable = whisper
        case .hybridLocalWhisper:
            let hybrid = Self.makeHybridLocalWhisperTranscriber(preloadOnStart: true)
            transcriber = hybrid
            localModelLoadingObservable = hybrid
        default:
            transcriber = Self.makeTranscriber(preloadOnStart: true)
            localModelLoadingObservable = nil
        }
        llmService = DefaultLLMService(azureFoundryConfig: azureConfig)
#if os(macOS)
        clipboardService = MacOSClipboardService.shared
        accessibilityService = MacOSAccessibilityService.shared
        hotkeyService = MacOSGlobalHotkeyService.shared
        claudeInboxService = MacOSClaudeInboxService.shared
#endif

        // 初始化 Use Cases
        editingUseCase = DefaultEditingUseCase()
        recordingUseCase = DefaultRecordingUseCase(coordinator: transcriber)
        transcriptionUseCase = DefaultTranscriptionUseCase(coordinator: transcriber, editing: editingUseCase)
        historyUseCase = DefaultHistoryUseCase(editing: editingUseCase)
        refinementUseCase = DefaultRefinementUseCase(llmService: llmService, editing: editingUseCase)

        // 启动时先用内存实现，避免 ModelContainer 创建阻塞 UI
        sessionUseCase = ProxySessionUseCase(backing: InMemorySessionUseCase())

        // Deep Link 路由
        deepLinkRouter = DefaultDeepLinkRouter()

#if os(macOS)
        // 快速录音使用独立 coordinator，避免主编辑器和快速录音串流/状态互相污染。
        // 本地 Whisper engine 在底层共享，不会重复下载同一模型。
        quickTranscriber = Self.makeQuickTranscriber()
        quickEditingUseCase = DefaultEditingUseCase()
        quickRecordingUseCase = DefaultRecordingUseCase(coordinator: quickTranscriber)
        quickTranscriptionUseCase = DefaultTranscriptionUseCase(
            coordinator: quickTranscriber,
            editing: quickEditingUseCase
        )
        quickRefinementUseCase = DefaultRefinementUseCase(
            llmService: llmService,
            editing: quickEditingUseCase
        )
#endif

        // 为所有多识别器 Transcriber 统一注入 LLM 合并器
        injectMergerIfNeeded(into: transcriber)
#if os(macOS)
        injectMergerIfNeeded(into: quickTranscriber)
#endif

        configureLLMService()
        observeProviderPreferenceChanges()
        Task { [weak self] in
            await self?.applyProviderPreferenceIfExists()
            await self?.applyAnalysisSettingsPreference()
        }

        logger.debug("Initialized")
    }

    private func observeProviderPreferenceChanges() {
        NotificationCenter.default.addObserver(
            forName: PreferencesNotification.llmProviderDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                await self?.applyProviderPreferenceIfExists()
            }
        }

        NotificationCenter.default.addObserver(
            forName: PreferencesNotification.llmAnalysisSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                await self?.applyAnalysisSettingsPreference()
            }
        }
    }

    private func applyAnalysisSettingsPreference() async {
        let skip: Bool = await preferencesStore.getValue(for: .llmSkipContentAnalysis, default: false)
        llmService.setSkipContentAnalysis(skip)
        logger.log(.debug, "Applied LLM analysis settings", context: [
            "skip_content_analysis": skip
        ])
    }

    private func applyProviderPreferenceIfExists() async {
        let stored: String? = await preferencesStore.getValue(for: .llmProvider)
        guard let stored, let preferred = LLMProviderType(rawValue: stored) else {
            return
        }
        configureLLMService(preferredProvider: preferred)
    }

    static func makeTranscriber(preloadOnStart: Bool = true) -> any TranscriptionCoordinator {
        switch LLMAppConfig.defaultTranscriberProvider {
        case .localWhisperKit:
            return LoadingFallbackTranscriptionCoordinator(
                primary: makeLocalWhisperTranscriber(preloadOnStart: preloadOnStart),
                fallback: AppleSpeechTranscriber()
            )
        case .hybridWhisper:
            if let config = makeAzureWhisperConfig() {
                return HybridWhisperTranscriber(whisperConfig: config)
            }
            return AppleSpeechTranscriber()
        case .azureWhisper:
            if let config = makeAzureWhisperConfig() {
                return AzureWhisperTranscriber(config: config)
            }
            return AppleSpeechTranscriber()
        case .hybridLocalWhisper:
            return HybridLocalWhisperTranscriber(
                config: LocalWhisperKitConfig(
                    model: LocalWhisperKitConfig.platformDefaultModel,
                    preloadOnStart: preloadOnStart
                )
            )
        case .appleSpeech:
            return AppleSpeechTranscriber()
        }
    }

    static func makeQuickTranscriber() -> any TranscriptionCoordinator {
        makeTranscriber(preloadOnStart: true)
    }

    private static func makeLocalWhisperTranscriber(preloadOnStart: Bool) -> WhisperKitTranscriber {
        WhisperKitTranscriber(
            config: LocalWhisperKitConfig(
                model: LocalWhisperKitConfig.platformDefaultModel,
                preloadOnStart: preloadOnStart
            )
        )
    }

    private static func makeHybridLocalWhisperTranscriber(preloadOnStart: Bool) -> HybridLocalWhisperTranscriber {
        HybridLocalWhisperTranscriber(
            config: LocalWhisperKitConfig(
                model: LocalWhisperKitConfig.platformDefaultModel,
                preloadOnStart: preloadOnStart
            )
        )
    }

    private static func makeAzureWhisperConfig() -> AzureWhisperConfig? {
        let env = ProcessInfo.processInfo.environment
        guard let apiKey = env["whisperkey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }
        // audio/transcriptions 保留原始语言（如中文）
        // audio/translations 会强制将所有音频翻译为英文
        let endpoint = URL(string: "https://tianp-mmd3pwyc-swedencentral.cognitiveservices.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-06-01")!
        return AzureWhisperConfig(endpoint: endpoint, apiKey: apiKey)
    }

    private static func makeAzureFoundryConfig() -> LLMProviderConfig? {
        guard let deployment = makeAzureFoundryDeployment() else {
            return nil
        }
        return deployment.providerConfig
    }

    /// 若 transcriber 遵循 MultiRecognizerTranscriber，注入 LLM 合并器
    private func injectMergerIfNeeded(into coordinator: any TranscriptionCoordinator) {
        guard var multiRecognizer = coordinator as? any MultiRecognizerTranscriber else { return }
        multiRecognizer.merger = LLMTranscriptionMerger(llmService: llmService)
    }

    private func configureLLMService(
        preferredProvider: LLMProviderType? = nil
    ) {
        let provider = preferredProvider
            ?? LLMAppConfig.defaultProvider

        var options: [String: String] = LLMAppConfig.analysisOptions()

        let modelIdentifier: String
        let apiKey: String?
        let baseURL: URL?

        switch provider {
        case .azureFoundry:
            if let deployment = Self.makeAzureFoundryDeployment() {
                modelIdentifier = deployment.model
                apiKey = deployment.apiKey
                baseURL = deployment.endpoint
                options["azure.api_version"] = deployment.apiVersion
                options["azure.auth_mode"] = deployment.authMode.rawValue
                options["azure.max_tokens"] = String(deployment.maxTokens)
                options["azure.top_p"] = String(deployment.topP)
                options["azure.presence_penalty"] = String(deployment.presencePenalty)
            } else {
                modelIdentifier = LLMAppConfig.azureModelIdentifier
                apiKey = nil
                baseURL = LLMAppConfig.azureEndpoint
                options["azure.api_version"] = LLMAppConfig.azureAPIVersion
            }
        default:
            modelIdentifier = "apple-intelligence"
            apiKey = nil
            baseURL = nil
        }

        let config = LLMProviderConfig(
            providerType: provider,
            apiKey: apiKey,
            baseURL: baseURL,
            modelIdentifier: modelIdentifier,
            options: options
        )

        do {
            try llmService.setProvider(config)
            logger.log(.debug, "Configured LLM provider", context: [
                "provider": provider.rawValue,
                "options_count": options.count
            ])
        } catch {
            logger.log(.debug, "LLM configuration failed; using fallback", context: [
                "provider": provider.rawValue,
                "error": error.localizedDescription
            ])
        }
    }

    private static func readAzureFoundryAPIKey() -> String? {
        // API Key 注入入口：
        // 1) 推荐：环境变量 `kimikey`
        // 2) 兼容：环境变量 `AZURE_API_KEY`、`VOX_AZURE_FOUNDRY_API_KEY`（历史命名）
        let env = ProcessInfo.processInfo.environment
        return env["kimikey"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? env["AZURE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? env["VOX_AZURE_FOUNDRY_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeAzureFoundryDeployment() -> AzureFoundryDeployment? {
        guard let apiKey = readAzureFoundryAPIKey(), !apiKey.isEmpty else {
            return nil
        }

        // Foundry 配置入口：在这里设置模型、URL、鉴权模式和 API Key
        return AzureFoundryDeployment(
            name: "default",
            endpoint: LLMAppConfig.azureEndpoint,
            model: LLMAppConfig.azureModelIdentifier,
            apiKey: apiKey,
            apiVersion: LLMAppConfig.azureAPIVersion,
            authMode: LLMAppConfig.azureAuthMode
        )
    }

    // MARK: - 遥测工厂

    /// 创建遥测服务
    ///
    /// Debug 默认连接本地 Docker Loki（`http://localhost:3100/loki/api/v1/push`）。
    /// Release 须通过 `LOKI_ENDPOINT` 环境变量显式指定，否则回退到 Noop。
    /// 可通过 `LOKI_TOKEN` 提供 Bearer token（Grafana Cloud）。
    private static func makeTelemetryService() -> any TelemetryService {
        let env = ProcessInfo.processInfo.environment

        let endpoint: URL
        if let urlString = env["LOKI_ENDPOINT"], let url = URL(string: urlString) {
            endpoint = url
        } else {
            #if DEBUG
            endpoint = URL(string: "http://localhost:3100/loki/api/v1/push")!
            #else
            return NoopTelemetryService()
            #endif
        }

        var labels: [String: String] = ["app": "VoxPocket"]
        #if DEBUG
        labels["env"] = "development"
        #else
        labels["env"] = "production"
        #endif
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            labels["version"] = version
        }

        return LokiTelemetryService(
            endpoint: endpoint,
            appLabels: labels,
            authToken: env["LOKI_TOKEN"]
        )
    }

    // MARK: - 延迟持久化初始化

    /// 延迟初始化 SwiftData 持久化层
    ///
    /// 在 UI 首次渲染后调用，避免 ModelContainer 创建阻塞 App 初始化导致 UI 卡死。
    public func initializePersistence() async {
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
            await sessionUseCase.switchBacking(to: swiftDataUseCase)
            logger.debug("SwiftData persistence initialized")
        } catch {
            logger.log(.debug, "Failed to initialize SwiftData persistence", context: [
                "error": error.localizedDescription
            ])
        }
    }

    // MARK: - ViewModel 工厂方法

    /// 创建完整面板的 EditorViewModel
    public func makeEditorViewModel() -> EditorViewModel {
#if os(macOS)
        let clipboard: ClipboardService? = MacOSClipboardService.shared
        let inbox: (any ClaudeInboxService)? = MacOSClaudeInboxService.shared
#else
        let clipboard: ClipboardService? = nil
        let inbox: (any ClaudeInboxService)? = nil
#endif
        return EditorViewModel(
            recording: recordingUseCase,
            transcription: transcriptionUseCase,
            editing: editingUseCase,
            history: historyUseCase,
            refinement: refinementUseCase,
            clipboard: clipboard,
            session: sessionUseCase,
            inbox: inbox
        )
    }

    /// 创建完整面板的 RootViewModel
    public func makeRootViewModel() -> RootViewModel<SessionListViewModel, EditorViewModel> {
        let editor = makeEditorViewModel()
        let sessionList = SessionListViewModel(sessionUseCase: sessionUseCase)
        return RootViewModel(sessionListState: sessionList, editorState: editor, deepLinkRouter: deepLinkRouter)
    }

    /// 创建快速录音的 ViewModel（使用独立服务栈，不影响主编辑器状态）
#if os(macOS)
    public func makeQuickRecordingViewModel() -> QuickRecordingViewModel {
        QuickRecordingViewModel(
            recordingUseCase: quickRecordingUseCase,
            transcriptionUseCase: quickTranscriptionUseCase,
            refinementUseCase: quickRefinementUseCase,
            clipboardService: clipboardService,
            telemetryService: telemetryService
        )
    }
#endif

    // MARK: - 录音状态管理

    /// 尝试开始录音
    /// - Parameter source: 录音来源
    /// - Returns: 是否成功开始
    public func tryStartRecording(source: RecordingSource) -> Bool {
        guard !isRecordingActive else {
            logger.log(.debug, "Recording request rejected because another source is active", context: [
                "active_source": activeRecordingSource?.rawValue ?? "unknown",
                "requested_source": source.rawValue
            ])
            return false
        }

        isRecordingActive = true
        activeRecordingSource = source
        logger.log(.debug, "Recording started", context: [
            "source": source.rawValue
        ])
        telemetryService.track(
            name: TelemetryEventName.recordingStarted.rawValue,
            properties: ["source": source.rawValue]
        )
        return true
    }

    /// 结束录音
    public func endRecording() {
        isRecordingActive = false
        activeRecordingSource = nil
        logger.debug("Recording ended")
        let svc = telemetryService
        Task { await svc.flush() }
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
    private var currentSessionSubscription: AnyCancellable?
    private let sessionsRelay = CurrentValueSubject<[Session], Error>([])
    private let currentSessionRelay = CurrentValueSubject<Session?, Never>(nil)

    init(backing: SessionUseCase) {
        self.backing = backing
        rebindPublisher()
    }

    /// 切换底层实现并重新加载数据
    func switchBacking(to newBacking: SessionUseCase) async {
        backing = newBacking
        rebindPublisher()
        // 等待数据加载完成，确保 UI 及时刷新
        _ = try? await fetchAllSessions()
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

        currentSessionSubscription = backing.currentSessionPublisher
            .sink { [weak self] session in
                self?.currentSessionRelay.send(session)
            }
    }

    // MARK: - SessionUseCase 转发

    public var currentSession: Session? { currentSessionRelay.value }

    public var currentSessionPublisher: AnyPublisher<Session?, Never> {
        currentSessionRelay.eraseToAnyPublisher()
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

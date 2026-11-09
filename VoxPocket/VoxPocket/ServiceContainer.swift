import VoxSpeechWhisperKit
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
import VoxSpeech
import VoxKitBridge
import VoxCore
import VoxLLM
import VoxWorkflow
import VoxWorkflowWhisperKit
import UseCases
import CoreModels
import Persistence
import PlatformAdapters
import Preferences
import UIShared
import LokiKit
#if os(macOS)
import PlatformUI
#elseif os(iOS)
import UIKit
import WidgetUI
#if canImport(ActivityKit)
import ActivityKit
#endif
#endif

/// 服务容器
///
/// 集中管理所有服务和用例实例，避免重复创建。
/// 提供工厂方法创建 ViewModel。
@MainActor
public final class ServiceContainer: ObservableObject {
    internal let preferencesStore: any PreferencesStore
    private let logger: Logger
    private let sdk: SDKHostConfiguration
    private let persistenceStartup = AppPersistenceStartup()
    private var iosPresetPreferenceBinding: IOSPresetPreferenceBinding?

    // MARK: - 单例

    public static let shared = ServiceContainer()

    // MARK: - 基础服务

    /// 主转录器：Apple 实时预览，配置齐全时使用 Azure 文件转写终稿。
    public let transcriber: any TranscriptionCoordinator
    public let localModelLoadingObservable: (any ModelLoadingObservable)?
    public let refinementRunner: RefineWorkflowRunner

    // MARK: - Use Cases

    public let editingUseCase: DefaultEditingUseCase
    public let recordingUseCase: DefaultRecordingUseCase
    public let transcriptionUseCase: DefaultTranscriptionUseCase
    public let historyUseCase: DefaultHistoryUseCase
    public let refinementUseCase: DefaultRefinementUseCase
    public let streamingInputCoordinator: DefaultStreamingInputCoordinator

    /// 会话用例代理（启动时用内存实现，后台初始化后切换到 SwiftData）
    public let sessionUseCase: ProxySessionUseCase

    /// Clean-Slate 语音速记与 AI Todo 用例
    public let voiceCaptureRepository: DefaultVoiceCaptureRepository
    public let voiceTodoRepository: DefaultVoiceTodoRepository
    public let aiRunnerService: DefaultAIRunnerExecutionService
    public let voiceCaptureAndTodoUseCase: DefaultVoiceCaptureAndTodoUseCase
    public private(set) lazy var workspaceViewModel: VoxWorkspaceViewModel = makeWorkspaceViewModel()

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
    public let quickStreamingInputCoordinator: DefaultStreamingInputCoordinator
    public let quickRefinementRunner: RefineWorkflowRunner
#endif

    // MARK: - 遥测

    public let telemetryService: any TelemetryService
    private let telemetryCoordinator: TelemetryLifecycleCoordinator
    private let productTelemetryPreferences: ProductTelemetryPreferences
    private var productTelemetryInstrumentation: ProductTelemetryInstrumentation!
    private var pendingProductTelemetryRecordingCompletion: Task<Void, Never>?

    // MARK: - 状态跟踪

    /// 当前是否有录音正在进行
    @Published public var isRecordingActive: Bool = false

    /// 活动的录音源标识
    @Published public var activeRecordingSource: RecordingSource? = nil

    // MARK: - 初始化

    init(
        productTelemetryPreferences: ProductTelemetryPreferences = ProductTelemetryPreferences(),
        processEnvironment: [String: String]? = nil, processArguments: [String] = ProcessInfo.processInfo.arguments,
        preferencesStore: any PreferencesStore = UserDefaultsPreferencesStore.shared,
        llmNotificationCenter: NotificationCenter = .default,
        productTelemetryConfiguration: @escaping ProductTelemetryConfigurationProvider = { BlobTelemetryConfiguration() },
        productTelemetryBootstrapFactory: ProductTelemetryBootstrapFactory? = nil, productTelemetryNotificationCenter: NotificationCenter = .default,
        productTelemetryHostOverride: BlobTelemetryHostKind? = nil
    ) {
        self.preferencesStore = preferencesStore
        let environment = processEnvironment ?? LLMAppConfig.runtimeEnvironment
        VoxPocketLogging.start(); logger = PrintLogger(subsystem: "ServiceContainer")
        let telemetryCoordinator = Self.makeTelemetryService()
        self.telemetryCoordinator = telemetryCoordinator; telemetryService = telemetryCoordinator
        let sdk = SDKHostConfiguration(storageLocations: SDKHostConfiguration.storageLocations(),
            logger: LokiVoxLogger(logger: logger), telemetry: LokiVoxTelemetry(service: telemetryCoordinator),
            credentials: SDKHostConfiguration.credentials(environment: environment))
        self.sdk = sdk
        let productTelemetry = ProductTelemetryAssembly.make(
            preferences: productTelemetryPreferences, environment: processEnvironment ?? ProcessInfo.processInfo.environment, arguments: processArguments,
            configuration: productTelemetryConfiguration, bootstrapFactory: productTelemetryBootstrapFactory,
            notificationCenter: productTelemetryNotificationCenter, hostOverride: productTelemetryHostOverride, coordinator: telemetryCoordinator
        )
        self.productTelemetryPreferences = productTelemetry.preferences; productTelemetryInstrumentation = productTelemetry.instrumentation
        let azureConfig = Self.makeAzureFoundryConfig(environment: environment)
        let availability = StageModelRouting.availability(environment: environment)
        #if os(macOS)
        let initialPreset = StagePresetMapping.preset(settings: LLMAppConfig.initialStageModelSettings,
            batchConfigured: availability.batchConfigured,
            realtimeConfigured: LLMAppConfig.realtimeTranscriptionConfig(environment: environment) != nil,
            azureTextConfigured: availability.textConfigured)
        #else
        let initialPreset = IOSPresetMapping.preset(batchConfigured: availability.batchConfigured,
            azureTextConfigured: availability.textConfigured)
        #endif
        let workflowConfiguration = Self.makeWorkflowConfiguration(environment: environment, sdk: sdk)
        refinementRunner = RefineWorkflowRunner(preset: initialPreset, configuration: workflowConfiguration,
                                                azureTextConfigured: availability.textConfigured)
        #if os(macOS)
        quickRefinementRunner = RefineWorkflowRunner(preset: initialPreset, configuration: workflowConfiguration,
                                                     azureTextConfigured: availability.textConfigured)
        #endif
        (transcriber, localModelLoadingObservable) = Self.makePrimaryTranscriber(environment: environment, preferences: preferencesStore,
            presetID: LLMAppConfig.defaultPresetID, sdk: sdk) { [weak refinementRunner] settings in
                let selected = StagePresetMapping.preset(settings: settings, batchConfigured: availability.batchConfigured,
                    realtimeConfigured: LLMAppConfig.realtimeTranscriptionConfig(environment: environment,
                        deploymentOverride: settings.realtimeDeployment) != nil, azureTextConfigured: availability.textConfigured)
                refinementRunner?.configure(preset: selected, configuration: workflowConfiguration,
                                            azureTextConfigured: availability.textConfigured)
            }
#if os(macOS)
        clipboardService = MacOSClipboardService.shared; accessibilityService = MacOSAccessibilityService.shared
        hotkeyService = MacOSGlobalHotkeyService.shared; claudeInboxService = MacOSClaudeInboxService.shared
#endif
        editingUseCase = DefaultEditingUseCase(); historyUseCase = DefaultHistoryUseCase(editing: editingUseCase); recordingUseCase = DefaultRecordingUseCase(coordinator: transcriber, telemetry: telemetryService)
        transcriptionUseCase = DefaultTranscriptionUseCase(coordinator: transcriber, editing: editingUseCase, telemetry: telemetryService)
        refinementUseCase = DefaultRefinementUseCase(runner: refinementRunner, editing: editingUseCase, telemetry: telemetryService)
        streamingInputCoordinator = DefaultStreamingInputCoordinator(editing: editingUseCase, transcription: transcriptionUseCase, refinement: refinementUseCase)
        let storageDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VoxPocket", isDirectory: true)
        voiceCaptureRepository = DefaultVoiceCaptureRepository(directoryURL: storageDirectory, cloudSync: UbiquitousKeyValueCloudSyncTransport())
        voiceTodoRepository = DefaultVoiceTodoRepository(directoryURL: storageDirectory, cloudSync: UbiquitousKeyValueCloudSyncTransport())
        aiRunnerService = DefaultAIRunnerExecutionService()
        let captureTodoUseCase = DefaultVoiceCaptureAndTodoUseCase(
            captures: voiceCaptureRepository,
            todos: voiceTodoRepository,
            extractor: DefaultVoiceTodoExtractor(),
            runner: aiRunnerService,
            telemetry: telemetryService
        )
        voiceCaptureAndTodoUseCase = captureTodoUseCase
        let productTelemetryInstrumentation = self.productTelemetryInstrumentation!
        sessionUseCase = ProxySessionUseCase(
            backing: InMemorySessionUseCase()
        ) { _, _ in
            await productTelemetryInstrumentation.sessionDidComplete()
        }
        deepLinkRouter = DefaultDeepLinkRouter()
#if os(macOS)
        quickTranscriber = Self.makeQuickTranscriber(environment: environment, preferences: preferencesStore,
            presetID: LLMAppConfig.defaultPresetID, sdk: sdk) { [weak quickRefinementRunner] settings in
                let selected = StagePresetMapping.preset(settings: settings, batchConfigured: availability.batchConfigured,
                    realtimeConfigured: LLMAppConfig.realtimeTranscriptionConfig(environment: environment,
                        deploymentOverride: settings.realtimeDeployment) != nil, azureTextConfigured: availability.textConfigured)
                quickRefinementRunner?.configure(preset: selected, configuration: workflowConfiguration,
                                                 azureTextConfigured: availability.textConfigured)
            }; quickEditingUseCase = DefaultEditingUseCase()
        quickRecordingUseCase = DefaultRecordingUseCase(coordinator: quickTranscriber, telemetry: telemetryService); quickTranscriptionUseCase = DefaultTranscriptionUseCase(coordinator: quickTranscriber, editing: quickEditingUseCase, telemetry: telemetryService); quickRefinementUseCase = DefaultRefinementUseCase(runner: quickRefinementRunner, editing: quickEditingUseCase, telemetry: telemetryService)
        quickStreamingInputCoordinator = DefaultStreamingInputCoordinator(editing: quickEditingUseCase, transcription: quickTranscriptionUseCase, refinement: quickRefinementUseCase)
#endif
        finishInitialization(environment: environment, notificationCenter: llmNotificationCenter)
    }

    private func finishInitialization(environment: [String: String], notificationCenter: NotificationCenter) {
        let productTelemetryInstrumentation = self.productTelemetryInstrumentation!
        let captureTodoUseCase = self.voiceCaptureAndTodoUseCase
        #if os(macOS)
        let captureDeviceSource: DeviceSource = .mac
        _ = notificationCenter
        #else
        let captureDeviceSource: DeviceSource = .iPhone
        let availability = StageModelRouting.availability(environment: environment)
        let workflowConfiguration = Self.makeWorkflowConfiguration(environment: environment, sdk: sdk)
        let runner = refinementRunner
        let binding = IOSPresetPreferenceBinding(batchConfigured: availability.batchConfigured,
            azureTextConfigured: availability.textConfigured, preferences: preferencesStore,
            notificationCenter: notificationCenter, logger: sdk.logger,
            onPresetChange: { preset in
                runner.configure(preset: preset, configuration: workflowConfiguration,
                                 azureTextConfigured: availability.textConfigured)
            })
        iosPresetPreferenceBinding = binding
        setupIOSLiveActivityAndIntentObservers(notificationCenter: notificationCenter)
        #endif
        sessionUseCase.onCompletedSession = { [weak self] rawText, refinedText in
            await productTelemetryInstrumentation.sessionDidComplete()
            let mode = await MainActor.run { self?.activeSessionCaptureMode ?? .text }
            _ = try? await captureTodoUseCase.recordCompletedCapture(
                mode: mode, rawTranscript: rawText, refinedText: refinedText,
                localAudioFileName: nil, durationSeconds: 0, deviceSource: captureDeviceSource
            )
            await MainActor.run {
                self?.reloadWorkspaceViewModel()
                if mode == .todo {
                    NotificationCenter.default.post(name: Notification.Name("vox.openFullPanel"), object: nil)
                }
            }
        }
        logger.debug("Initialized")
    }

    private static func makePrimaryTranscriber(
        environment: [String: String], preferences: any PreferencesStore,
        presetID: String, sdk: SDKHostConfiguration,
        beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)? = nil
    ) -> (any TranscriptionCoordinator, (any ModelLoadingObservable)?) {
        let wrapped = makeTranscriber(environment: environment, preferences: preferences, presetID: presetID, sdk: sdk, beforeSession: beforeSession)
        if let source = (wrapped.core as? any ModelLoadingStateProviding)
            ?? (wrapped.core as? LoadingFallbackTranscriptionCoordinator)?.primaryModelLoadingSource {
            return (wrapped, CombineModelLoadingObservable(source: source))
        }
        return (wrapped, nil)
    }

    func waitForPendingLLMPreferenceChanges() async { await iosPresetPreferenceBinding?.waitForPendingChanges() }

    static func makeTranscriber(
        preloadOnStart: Bool = true, environment: [String: String]? = nil,
        preferences: any PreferencesStore = UserDefaultsPreferencesStore.shared,
        presetID: String = LLMAppConfig.defaultPresetID, sdk: SDKHostConfiguration? = nil,
        beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)? = nil
    ) -> WorkflowTranscriptionCoordinator {
        let environment = environment ?? LLMAppConfig.runtimeEnvironment
        let sdk = sdk ?? SDKHostConfiguration(storageLocations: SDKHostConfiguration.storageLocations(),
            logger: LokiVoxLogger(logger: PrintLogger(subsystem: "ServiceContainer")),
            telemetry: NoopVoxTelemetry(), credentials: SDKHostConfiguration.credentials(environment: environment))
        let availability = StageModelRouting.availability(environment: environment)
        let preset = Self.preset(for: presetID, availability: availability, environment: environment)
        let core: any SpeechSessionSource
        switch presetID {
        case "local.whisperkit":
            core = LoadingFallbackTranscriptionCoordinator(
                primary: WhisperKitTranscriber(config: LocalWhisperKitConfig(preloadOnStart: preloadOnStart),
                    logger: sdk.logger, telemetry: sdk.telemetry, storageLocations: sdk.storageLocations),
                fallback: AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations))
        case "hybrid.azure":
            #if os(macOS)
            core = StageModelRouting.makeTranscriber(environment: environment, preferences: preferences, sdk: sdk,
                                                     beforeSession: beforeSession)
            #else
            core = makeIOSHybridSource(environment: environment, sdk: sdk)
            #endif
        case "azure.whisper":
            if let config = LLMAppConfig.transcriptionConfig(environment: environment) {
                core = AzureWhisperTranscriber(config: config, logger: sdk.logger, storageLocations: sdk.storageLocations)
            } else { core = AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations) }
        case "hybrid.local":
            let provider = Self.makeAzureFoundryConfig(environment: environment).map {
                AzureFoundryProvider(config: $0, logger: sdk.logger)
            }
            core = makeHybridLocalWhisperTranscriber(preloadOnStart: preloadOnStart,
                merger: provider.map { LLMTranscriptionMerger(provider: $0, logger: sdk.logger) }, sdk: sdk)
        case "apple.speech":
            core = AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations)
        default:
            core = AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations)
        }
        return WorkflowTranscriptionCoordinator(source: core, preset: preset)
    }

    static func makeQuickTranscriber(environment: [String: String]? = nil,
                                    preferences: any PreferencesStore = UserDefaultsPreferencesStore.shared,
                                    presetID: String = LLMAppConfig.defaultPresetID, sdk: SDKHostConfiguration? = nil,
                                    beforeSession: (@MainActor @Sendable (StageModelSettings) -> Void)? = nil) -> WorkflowTranscriptionCoordinator {
        makeTranscriber(environment: environment, preferences: preferences, presetID: presetID,
                        sdk: sdk, beforeSession: beforeSession)
    }

    static func makeIOSHybridTranscriber(environment: [String: String]) -> WorkflowTranscriptionCoordinator {
        let sdk = SDKHostConfiguration(storageLocations: SDKHostConfiguration.storageLocations(),
            logger: LokiVoxLogger(logger: PrintLogger(subsystem: "ServiceContainer")),
            telemetry: NoopVoxTelemetry(), credentials: SDKHostConfiguration.credentials(environment: environment))
        return WorkflowTranscriptionCoordinator(source: makeIOSHybridSource(environment: environment, sdk: sdk), preset: .hybridAzure)
    }

    private static func makeIOSHybridSource(environment: [String: String], sdk: SDKHostConfiguration) -> any SpeechSessionSource {
        if let config = LLMAppConfig.transcriptionConfig(environment: environment) {
            return HybridWhisperTranscriber(whisperConfig: config,
                realtimeConfig: LLMAppConfig.realtimeTranscriptionConfig(environment: environment),
                logger: sdk.logger, storageLocations: sdk.storageLocations)
        }
        PrintLogger(subsystem: "ServiceContainer").warning("Azure transcription configuration missing; actual_provider=appleSpeech")
        return AppleSpeechTranscriber(logger: sdk.logger, storageLocations: sdk.storageLocations)
    }

    private static func makeHybridLocalWhisperTranscriber(preloadOnStart: Bool,
        merger: (any TranscriptionMerger)?, sdk: SDKHostConfiguration) -> HybridLocalWhisperTranscriber {
        HybridLocalWhisperTranscriber(config: LocalWhisperKitConfig(preloadOnStart: preloadOnStart),
            logger: sdk.logger, merger: merger, storageLocations: sdk.storageLocations)
    }

    private static func preset(for presetID: String, availability: ModelSettingsAvailability,
                               environment: [String: String]) -> Preset {
        switch presetID {
        case "apple.speech": return .appleSpeech
        case "local.whisperkit": return .localWhisperKit
        case "hybrid.local": return .hybridLocal
        case "azure.whisper": return .hybridAzure.overriding(["speech": "azureWhisper"])
        default:
            #if os(macOS)
            return StagePresetMapping.preset(settings: LLMAppConfig.initialStageModelSettings,
                batchConfigured: availability.batchConfigured,
                realtimeConfigured: LLMAppConfig.realtimeTranscriptionConfig(environment: environment) != nil,
                azureTextConfigured: availability.textConfigured)
            #else
            return IOSPresetMapping.preset(batchConfigured: availability.batchConfigured,
                azureTextConfigured: availability.textConfigured)
            #endif
        }
    }

    private static func makeWorkflowConfiguration(environment: [String: String], sdk: SDKHostConfiguration) -> WorkflowExecutionConfiguration {
        WorkflowExecutionConfiguration(azureFoundryConfig: makeAzureFoundryConfig(environment: environment),
            whisperConfig: LLMAppConfig.transcriptionConfig(environment: environment),
            realtimeConfig: LLMAppConfig.realtimeTranscriptionConfig(environment: environment),
            logger: sdk.logger, telemetry: sdk.telemetry, storageLocations: sdk.storageLocations)
    }

    static func makeAzureFoundryConfig(environment: [String: String]) -> LLMProviderConfig? {
        guard let deployment = makeAzureFoundryDeployment(environment: environment) else {
            // Azure 缺配置时明确失败，不静默调用 Apple 精炼。
            return LLMProviderConfig(providerType: .azureFoundry, modelIdentifier: LLMAppConfig.azureModelIdentifier(environment: environment))
        }
        return deployment.providerConfig
    }

    static func makeProviderConfig(
        _ provider: LLMProviderType, environment: [String: String]
    ) -> (LLMProviderConfig, Int) {
        var options: [String: String] = LLMAppConfig.analysisOptions()
        let modelIdentifier: String
        let apiKey: Credential?
        let baseURL: URL?
        switch provider {
        case .azureFoundry:
            if let deployment = Self.makeAzureFoundryDeployment(environment: environment) {
                modelIdentifier = deployment.model
                apiKey = deployment.apiKey
                baseURL = deployment.endpoint
                options["azure.api_version"] = deployment.apiVersion
                options["azure.auth_mode"] = deployment.authMode.rawValue
                options["azure.max_tokens"] = String(deployment.maxTokens)
                options["azure.top_p"] = String(deployment.topP)
                options["azure.presence_penalty"] = String(deployment.presencePenalty)
                options["azure.api_style"] = deployment.apiStyle.rawValue
                options["azure.reasoning_effort"] = deployment.reasoningEffort
            } else {
                modelIdentifier = LLMAppConfig.azureModelIdentifier(environment: environment)
                apiKey = nil
                baseURL = LLMAppConfig.azureEndpoint(environment: environment)
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
        return (config, options.count)
    }

    private static func makeAzureFoundryDeployment(environment: [String: String]) -> AzureFoundryDeployment? {
        guard let apiKey = LLMAppConfig.refinementAPIKey(environment: environment), !apiKey.isEmpty,
              let endpoint = LLMAppConfig.azureEndpoint(environment: environment) else {
            return nil
        }

        // Foundry 配置入口：在这里设置模型、URL、鉴权模式和 API Key
        return AzureFoundryDeployment(
            name: "default",
            endpoint: endpoint,
            model: LLMAppConfig.azureModelIdentifier(environment: environment),
            apiKey: Credential(rawValue: apiKey),
            apiVersion: LLMAppConfig.azureAPIVersion,
            authMode: LLMAppConfig.azureAuthMode,
            apiStyle: LLMAppConfig.azureAPIStyle,
            reasoningEffort: "none"
        )
    }

    // MARK: - 遥测工厂

    /// 创建遥测服务
    ///
    /// Debug 默认连接本地 Docker Loki（`http://localhost:3100/loki/api/v1/push`）。
    /// Release 须通过 `LOKI_ENDPOINT` 环境变量显式指定，否则回退到 Noop。
    /// 可通过 `LOKI_TOKEN` 提供 Bearer token（Grafana Cloud）。
    private static func makeTelemetryService() -> TelemetryLifecycleCoordinator {
        let env = ProcessInfo.processInfo.environment

        let endpoint: URL
        if let urlString = env["LOKI_ENDPOINT"], let url = URL(string: urlString) {
            endpoint = url
        } else {
            #if DEBUG
            endpoint = URL(string: "http://localhost:3100/loki/api/v1/push")!
            #else
            return TelemetryLifecycleCoordinator(isEnabled: false) {
                NoopTelemetryService()
            }
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

        let authToken = env["LOKI_TOKEN"]
        return TelemetryLifecycleCoordinator {
            LokiTelemetryService(
                endpoint: endpoint,
                appLabels: labels,
                authToken: authToken
            )
        }
    }

    static let uiTestHostEnvironmentKey = "VOXPOCKET_UI_TEST_HOST"

    static func classifyBlobTelemetryHost(
        environment: [String: String],
        arguments: [String]
    ) -> BlobTelemetryHostKind {
        if environment[uiTestHostEnvironmentKey] == "1"
            && arguments.contains("--vox-ui-test-host") {
            return .test
        }
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil {
            return .test
        }
        return .interactiveApplication
    }

    static var blobTelemetryStoreDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoxPocket", isDirectory: true)
            .appendingPathComponent("ProductTelemetry", isDirectory: true)
    }

    func completeProductTelemetryStartup(startedAt: ContinuousClock.Instant) async {
        await productTelemetryInstrumentation.completeStartup(startedAt: startedAt)
    }

    func waitForPendingProductTelemetryStartupCompletion() async {
        await productTelemetryInstrumentation.waitForPendingStartupCompletion()
    }

    func recordProductAction(_ action: BlobProductAction) {
        productTelemetryInstrumentation.record(action)
    }

    func productTelemetryApplicationWillResignActive() async {
        await productTelemetryInstrumentation.applicationWillResignActive()
    }

    func waitForPendingProductTelemetryConsentChange() async {
        await productTelemetryInstrumentation.waitForPendingConsentChange()
    }

    // MARK: - 延迟持久化初始化

    /// 延迟初始化 SwiftData 持久化层
    ///
    /// 后台启动与保存入口共享同一初始化；数据库打开不占用主线程。
    public func initializePersistence() async {
        let ready = await persistenceStartup.prepare { [self] in
            let repository = try await Self.makeSessionRepository()
            let swiftDataUseCase = DefaultSessionUseCase(repository: repository, telemetry: telemetryService)
            await sessionUseCase.switchBacking(to: swiftDataUseCase)
            logger.debug("SwiftData persistence initialized")
        }
        if !ready {
            logger.error("Session persistence could not be initialized")
        }
    }

    nonisolated private static func makeSessionRepository() async throws -> SwiftDataSessionRepository {
        try await Task.detached(priority: .utility) {
            let schema = Schema([SessionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            return SwiftDataSessionRepository(container: container)
        }.value
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
            inbox: inbox,
            streamingCoordinator: streamingInputCoordinator
        )
    }

    /// 创建完整面板的 RootViewModel
    public func makeRootViewModel() -> RootViewModel<SessionListViewModel, EditorViewModel> {
        let editor = makeEditorViewModel()
        let sessionList = SessionListViewModel(sessionUseCase: sessionUseCase)
        let root = RootViewModel(sessionListState: sessionList, editorState: editor, deepLinkRouter: deepLinkRouter)
        #if os(iOS)
        root.onStartRecordingInDefaultMode = { [weak self] in
            self?.workspaceViewModel.startCaptureInPreferredMode()
        }
        #endif
        root.onStartRecordingInMode = { [weak self, weak editor] mode in
            self?.workspaceViewModel.selectedCaptureMode = mode
            if mode == .todo {
                self?.workspaceViewModel.startCapture(mode: .todo)
            } else {
                #if os(iOS)
                self?.workspaceViewModel.startCapture(mode: .text)
                #else
                await editor?.startRecording()
                #endif
            }
        }
        root.onStopRecordingInMode = { [weak self, weak editor] mode in
            if mode == .todo || self?.workspaceViewModel.isRecordingActive == true {
                #if os(iOS)
                await self?.workspaceViewModel.completeCapture(deviceSource: .iPhone)
                #else
                await self?.workspaceViewModel.completeCapture()
                #endif
            } else {
                await editor?.stopRecording()
            }
        }
        return root
    }

    public var activeSessionCaptureMode: CaptureMode = .text {
        didSet {
            workspaceViewModel.selectedCaptureMode = activeSessionCaptureMode
        }
    }

    public func reloadWorkspaceViewModel() {
        Task { await workspaceViewModel.reload() }
    }

    /// 供 Action Button (`StartRecordingIntent`)、Widget (`ToggleQuickCaptureIntent`) 与灵动岛后台一键启停录音（不跳进主 App）。
    public func toggleQuickCaptureFromIntent() async {
        await initializePersistence()
        #if os(iOS)
        let source: DeviceSource = .iPhone
        #else
        let source: DeviceSource = .mac
        #endif
        if workspaceViewModel.isRecordingActive {
            await workspaceViewModel.completeCapture(deviceSource: source)
        } else {
            let preferredMode: CaptureMode = await preferencesStore.getValue(
                for: .iosQuickCaptureDestination,
                default: .todo
            )
            workspaceViewModel.startCapture(mode: preferredMode)
        }
    }

#if os(iOS)
    private func setupIOSLiveActivityAndIntentObservers(notificationCenter: NotificationCenter) {
        notificationCenter.addObserver(
            forName: ToggleQuickCaptureIntent.didRequestToggleNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.toggleQuickCaptureFromIntent()
            }
        }
        notificationCenter.addObserver(
            forName: FinishCaptureIntent.didRequestFinishNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.workspaceViewModel.isRecordingActive else { return }
                await self.workspaceViewModel.completeCapture(deviceSource: .iPhone)
            }
        }
        notificationCenter.addObserver(
            forName: Notification.Name("vox.liveActivity.recordingStarted"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let modeRaw = (note.userInfo?["mode"] as? String) ?? CaptureMode.todo.rawValue
            Task { @MainActor in
                self?.startIOSCaptureLiveActivity(modeRaw: modeRaw)
            }
        }
        notificationCenter.addObserver(
            forName: Notification.Name("vox.liveActivity.elapsedUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let seconds = (note.userInfo?["seconds"] as? Int) ?? 0
            let modeRaw = (note.userInfo?["mode"] as? String) ?? CaptureMode.todo.rawValue
            Task { @MainActor in
                self?.updateIOSCaptureLiveActivity(seconds: seconds, modeRaw: modeRaw)
            }
        }
        notificationCenter.addObserver(
            forName: Notification.Name("vox.liveActivity.recordingEnded"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endIOSCaptureLiveActivities()
            }
        }
    }

    private func startIOSCaptureLiveActivity(modeRaw: String) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let modeTitle = modeRaw == CaptureMode.todo.rawValue ? "存入待办" : "复制文字"
        let attributes = VoxCaptureActivityAttributes(sessionID: UUID().uuidString)
        let content = ActivityContent(
            state: VoxCaptureActivityAttributes.ContentState(
                mode: modeTitle,
                elapsedSeconds: 0,
                isRecording: true
            ),
            staleDate: nil
        )
        _ = try? Activity.request(attributes: attributes, content: content)
        #endif
    }

    private func updateIOSCaptureLiveActivity(seconds: Int, modeRaw: String) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let modeTitle = modeRaw == CaptureMode.todo.rawValue ? "存入待办" : "复制文字"
        let updated = ActivityContent(
            state: VoxCaptureActivityAttributes.ContentState(
                mode: modeTitle,
                elapsedSeconds: seconds,
                isRecording: true
            ),
            staleDate: nil
        )
        Task {
            for activity in Activity<VoxCaptureActivityAttributes>.activities {
                await activity.update(updated)
            }
        }
        #endif
    }

    private func endIOSCaptureLiveActivities() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        Task {
            for activity in Activity<VoxCaptureActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
#endif

    public func makeWorkspaceViewModel() -> VoxWorkspaceViewModel {
        #if os(iOS)
        let defaultMode: CaptureMode = .todo
        let copyHandler: (@MainActor @Sendable (String) -> Void)? = { text in
            UIPasteboard.general.string = text
        }
        #else
        let defaultMode: CaptureMode = .text
        let copyHandler: (@MainActor @Sendable (String) -> Void)? = { text in
            MacOSClipboardService.shared.copy(text)
        }
        #endif
        return VoxWorkspaceViewModel(
            useCase: voiceCaptureAndTodoUseCase,
            preferencesStore: preferencesStore,
            defaultCaptureMode: defaultMode,
            onCopyTextToClipboard: copyHandler,
            recordingUseCase: recordingUseCase,
            transcriptionUseCase: transcriptionUseCase,
            editingUseCase: editingUseCase,
            refinementUseCase: refinementUseCase
        )
    }

    /// 创建快速录音的 ViewModel（使用独立服务栈，不影响主编辑器状态）
#if os(macOS)
    public func makeQuickRecordingViewModel() -> QuickRecordingViewModel {
        QuickRecordingViewModel(
            recordingUseCase: quickRecordingUseCase,
            transcriptionUseCase: quickTranscriptionUseCase,
            refinementUseCase: quickRefinementUseCase,
            clipboardService: clipboardService,
            streamingCoordinator: quickStreamingInputCoordinator,
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
            name: VoxPocketTelemetryEventName.recordingStarted.rawValue,
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
        let productTelemetryInstrumentation = productTelemetryInstrumentation!
        pendingProductTelemetryRecordingCompletion = Task {
            await productTelemetryInstrumentation.recordingDidComplete()
        }
    }

    func waitForPendingProductTelemetryRecordingCompletion() async {
        await pendingProductTelemetryRecordingCompletion?.value
    }

    func waitForPendingProductTelemetrySessionCompletion() async {
        await productTelemetryInstrumentation.waitForPendingSessionCompletion()
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
    var onCompletedSession: @Sendable (String, String) async -> Void
    private var sessionsSubscription: AnyCancellable?
    private var currentSessionSubscription: AnyCancellable?
    private let sessionsRelay = CurrentValueSubject<[Session], Error>([])
    private let currentSessionRelay = CurrentValueSubject<Session?, Never>(nil)

    init(
        backing: SessionUseCase,
        onCompletedSession: @escaping @Sendable (String, String) async -> Void = { _, _ in }
    ) {
        self.backing = backing
        self.onCompletedSession = onCompletedSession
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
        let session = try await backing.saveCompletedSession(
            title: title,
            rawText: rawText,
            refinedText: refinedText
        )
        await onCompletedSession(rawText, refinedText)
        return session
    }
}

---
layer: VoxPocketApp
role: Xcode App 壳 —— 入口、ServiceContainer 组装、平台场景、Widget 扩展与交付配置
owns: [VoxPocket/**, VoxPocketWidget/**]
depends_on: [VoxDomain, VoxInfrastructure, VoxApplication, VoxPresentation]
gate:
  startup: python3 scripts/tests/test_app_startup.py
  interaction: python3 scripts/tests/test_startup_interaction.py
  menu-bar: python3 scripts/tests/test_menu_bar_launch.py
  quick-record: python3 scripts/tests/test_quick_record_release.py
  realtime-config: python3 scripts/tests/test_realtime_config.py
  logging: python3 scripts/tests/test_app_logging.py
red_lines:
  - 只做组装与平台接线;业务逻辑放进对应 Packages layer(宪法 II)
  - 私密模型配置只在沙箱运行时读取,不进 Git、日志或安装包;只提交凭据为空的模板(宪法 V)
  - 转写/精炼文本与音频不进日志或遥测负载(宪法 IV)
  - project.yml 是 Xcode 工程的唯一事实源;改 target 配置必须同步 project.yml
  - 交付只经 TestFlight(testflight.yml);本地不自动生成、安装或替换交付 build
---

# VoxPocketApp Tech Context

## 职责
`VoxPocket/VoxPocket/`:App 入口(`VoxPocketApp`、`AppDelegate`)、`@MainActor` 单例 DI 容器
`ServiceContainer`、macOS 场景与 `WindowManager` 浮窗、启动与私密配置加载。
`VoxPocket/project.yml`(XcodeGen)生成 `VoxPocket.xcodeproj`;`VoxPocketWidget/` 是仅 iOS 的 Widget 扩展。

## 依赖
- **仓库内**:通过 `VoxPresentation` 的 `UIShared`/`PlatformUI`/`WidgetUI` 产品,并直接 import
  `VoxInfrastructure`(TranscriptionKit/LLMKit/Persistence/PlatformAdapters/Preferences)、
  `VoxApplication`(UseCases)与 `VoxDomain`(CoreModels)的模块。
- **外部**:`LokiKit`(shared-telemetry,固定 SHA)与 `AppleUITesting`(`UITestingBridge`),
  均放在仓库同级目录,CI 由 `scripts/ci/fetch-external-deps.sh` 按固定 SHA 取出。

## ServiceContainer 初始化顺序
`ServiceContainer.init()` 在主线程同步执行:Logger + 遥测 → 转写器(`LLMAppConfig.defaultTranscriberProvider`)
→ `DefaultLLMService` 与 macOS 平台服务 → UseCases(Editing → Recording → Transcription → Refinement)
→ `ProxySessionUseCase` 先用 `InMemorySessionUseCase`,首帧后 `initializePersistence()` 热切到
`SwiftDataSessionUseCase` → macOS 独立的快捷录音栈(与主编辑器隔离,防状态串扰)。

## 门禁
- 本地/CI `gate`:上表 Python 回归(不构建签名 App)。
- CI 额外执行 `xcodebuild` 全量构建:macOS 与 iOS generic(`App target`,required),
  以及 iOS 模拟器 build/test(`iOS simulator`,non-required)。本地不跑 xcodebuild
  (`RUN_HEAVY=1 scripts/verify` 可显式开启 macOS 构建)。
- 测试注意:`swift test` 会一起编译一个包的所有 test target,某个 target 的既有失败会阻塞其他 target;
  定位单类用 `--filter`。

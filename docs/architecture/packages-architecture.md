# VoxPocket 包架构梳理

## 概览

VoxPocket 采用经典的 **Clean Architecture** 分层设计，通过 Swift Package Manager 将代码组织成4个独立的包，实现清晰的依赖方向和职责分离。

```
┌─────────────────────────────────────────┐
│       VoxPresentation (UI Layer)        │
│  ├─ UIShared: ViewModels, Components    │
│  └─ PlatformUI: Platform-specific UI    │
└─────────────────┬───────────────────────┘
                  │ depends on
┌─────────────────▼───────────────────────┐
│    VoxApplication (Use Case Layer)      │
│  └─ UseCases: Business logic flows      │
└─────────────────┬───────────────────────┘
                  │ depends on
      ┌───────────┴───────────┐
      │                       │
┌─────▼──────────┐  ┌─────────▼──────────┐
│  VoxDomain     │  │ VoxInfrastructure  │
│  (Entities)    │  │  (Adapters)        │
└────────────────┘  └────────────────────┘
```

## 依赖规则

**核心原则**: 依赖方向永远指向内层（Domain），外层依赖内层，内层不知道外层的存在。

- **VoxDomain**: 无外部依赖（纯业务实体）
- **VoxInfrastructure**: 仅依赖 VoxDomain
- **VoxApplication**: 依赖 VoxDomain + VoxInfrastructure
- **VoxPresentation**: 依赖所有层（最外层）

---

## 1. VoxDomain（领域层）

**定位**: 核心业务实体和领域模型，完全独立，无任何外部依赖。

### 1.1 CoreModels
**职责**: 核心数据模型和类型定义

**文件列表**:
- `Session.swift` - 录音会话实体
- `SessionState.swift` - 会话状态枚举
- `Checkpoint.swift` - 文本编辑检查点
- `Patch.swift` - 文本差异补丁
- `TextRange.swift` - 文本范围工具
- `ChangeSource.swift` - 变更来源追踪
- `VoxError.swift` - 统一错误类型

**关键特性**:
- 纯值类型（Struct/Enum）
- 无任何外部依赖
- 可被所有层引用

### 1.2 TextHistory
**职责**: 文本历史管理领域逻辑

**依赖**: CoreModels

**功能**: 提供文本版本控制和历史追溯的领域模型

---

## 2. VoxInfrastructure（基础设施层）

**定位**: 技术实现和外部系统适配器，提供具体的技术能力。

### 2.1 TranscriptionKit
**职责**: 语音转文字服务

**依赖**:
- CoreModels (数据模型)
- Observability (日志/监控)
- WhisperKit (Core ML 本地模型推理)

**功能**:
- 默认使用 `WhisperKitTranscriber` 做本地实时转录（`localWhisperKit`）
- 保留 `AppleSpeechTranscriber`、`HybridWhisperTranscriber`、`AzureWhisperTranscriber` 作为回退路径
- 提供 partial/final 事件流、音频电平流、失败遥测
- 错误处理与故障上报（模型加载失败、启动失败）

### 2.2 LLMKit
**职责**: 大语言模型服务

**依赖**:
- CoreModels
- TranscriptionKit (转录结果处理)
- Observability
- AsyncAlgorithms (异步流处理)

**结构**:
```
LLMKit/
├── Providers/     # LLM 提供商实现 (OpenAI, Anthropic, etc.)
├── Models/        # LLM 请求/响应模型
├── Protocols/     # 服务协议定义
├── Services/      # 具体服务实现
└── Utilities/     # 工具函数
```

**功能**:
- 多 LLM 提供商支持
- 流式响应处理
- Prompt 管理
- Token 计数和成本估算

### 2.3 Persistence
**职责**: 数据持久化

**依赖**:
- CoreModels (保存实体)
- TextHistory (历史记录存储)

**功能**:
- Session 存储和检索
- 文本历史持久化
- 本地缓存管理

### 2.4 Observability
**职责**: 可观测性（日志、监控、追踪）

**依赖**: CoreModels

**功能**:
- 结构化日志
- 性能追踪
- 错误上报

### 2.5 PlatformAdapters
**职责**: 平台特定功能适配

**依赖**:
- CoreModels
- Observability

**功能**:
- 系统剪贴板访问
- 文件系统操作
- 通知和权限管理

### 2.6 Preferences
**职责**: 用户偏好设置管理

**依赖**: 无

**功能**:
- 用户设置持久化
- 主题、语言等配置

---

## 3. VoxApplication（应用层）

**定位**: 业务用例编排，协调 Domain 和 Infrastructure 完成具体业务流程。

### 3.1 UseCases（用例集合）

**依赖**:
- VoxDomain: CoreModels, TextHistory
- VoxInfrastructure: TranscriptionKit, LLMKit, Persistence, Observability, PlatformAdapters

**用例列表**:

| 用例 | 协议 | 实现 | 职责 |
|------|------|------|------|
| Recording | `RecordingUseCase` | `DefaultRecordingUseCase` | 录音流程控制 |
| Transcription | `TranscriptionUseCase` | `DefaultTranscriptionUseCase` | 转录流程管理 |
| Intent Recognition | `IntentRecognitionUseCase` | `DefaultIntentRecognitionUseCase` | 意图识别（LLM） |
| Refinement | `RefinementUseCase` | `DefaultRefinementUseCase` | 文本精炼（LLM） |
| Editing | `EditingUseCase` | `DefaultEditingUseCase` | 文本编辑逻辑 |
| History | `HistoryUseCase` | `DefaultHistoryUseCase` | 历史管理 |
| Session | `SessionUseCase` | - | 会话生命周期 |
| Text Injection | `TextInjectionUseCase` | - | 文本注入系统 |

**工厂模式**:
- `UseCaseFactory.swift` - 统一创建和管理用例实例

**核心特点**:
- 每个用例对应一个具体业务流程
- 协议定义接口，Default实现提供默认逻辑
- 可独立测试，易于替换实现

---

## 4. VoxPresentation（展示层）

**定位**: 用户界面和交互逻辑，负责视图状态管理和用户交互。

### 4.1 UIShared（共享UI组件）

**依赖**:
- VoxDomain: CoreModels, TextHistory
- VoxInfrastructure: LLMKit, TranscriptionKit, PlatformAdapters, Preferences
- VoxApplication: UseCases

**结构**:
```
UIShared/
├── ViewModels/        # MVVM 视图模型
│   ├── EditorViewModel.swift
│   ├── RefinementViewModel.swift
│   ├── RootViewModel.swift
│   ├── SessionListViewModel.swift
│   ├── ShortcutsViewModel.swift
│   ├── VoxPocketViewModel.swift
│   └── Mocks/         # 测试用 Mock
├── DesignSystem/      # 设计系统（主题、颜色、字体）
├── Components/        # 可复用UI组件
├── Views/             # 通用视图
├── ViewStates/        # 视图状态模型
├── Models/            # UI专用模型
└── Snackbar/          # 通知组件
```

**ViewModels 职责**:
- **EditorViewModel**: 编辑器核心逻辑，管理文本编辑状态
- **RefinementViewModel**: 文本精炼流程控制
- **RootViewModel**: 根视图协调器
- **SessionListViewModel**: 会话列表管理
- **ShortcutsViewModel**: 快捷键和快捷操作
- **VoxPocketViewModel**: 主应用视图模型

### 4.2 PlatformUI（平台UI）

**依赖**:
- UIShared (复用组件)
- VoxDomain: CoreModels
- VoxInfrastructure: PlatformAdapters, Preferences, LLMKit, TranscriptionKit
- VoxApplication: UseCases

**职责**:
- iOS/macOS 平台特定视图
- 原生控件集成
- 平台特定交互模式

---

## 数据流示例

### 录音到文本的完整流程

```
[用户点击录音]
       ↓
[PlatformUI] - 用户交互
       ↓
[EditorViewModel] - 状态管理
       ↓
[RecordingUseCase] - 录音流程编排
       ↓
[TranscriptionKit] - 默认走本地 WhisperKit（可按配置切换）
       ↓
[Session (CoreModels)] - 更新会话数据
       ↓
[Persistence] - 保存到磁盘
       ↓
[EditorViewModel] - 更新UI状态
       ↓
[PlatformUI] - 显示转录结果
```

### LLM 精炼流程

```
[用户选择文本 + 触发精炼]
       ↓
[RefinementViewModel] - 精炼请求
       ↓
[RefinementUseCase] - 业务逻辑
       ↓ (并行)
├─ [IntentRecognitionUseCase] - 识别用户意图
│        ↓
│   [LLMKit] - OpenAI/Anthropic API
│        ↓
│   返回意图（修正/扩展/润色/等）
│
└─ [RefinementUseCase] - 基于意图执行精炼
       ↓
   [LLMKit] - 流式生成精炼文本
       ↓
   [Checkpoint (CoreModels)] - 创建编辑检查点
       ↓
   [Persistence] - 保存历史
       ↓
   [RefinementViewModel] - 更新UI
       ↓
   [EditorView] - 实时显示精炼结果
```

---

## 测试策略

### 测试金字塔

```
         ┌─────────────┐
         │  UI Tests   │  (PlatformUI)
         └─────────────┘
       ┌───────────────────┐
       │ Integration Tests │  (UseCases)
       └───────────────────┘
    ┌───────────────────────────┐
    │      Unit Tests           │  (Domain + Infrastructure)
    └───────────────────────────┘
```

**每个包的测试目标**:
- **CoreModels**: 值类型逻辑、序列化
- **TextHistory**: 历史追踪算法
- **TranscriptionKit/LLMKit**: Mock 外部服务
- **Persistence**: 存储读写正确性
- **UseCases**: 业务流程完整性（依赖注入 Mock）
- **UIShared**: ViewModel 状态变化

---

## 设计模式应用

| 模式 | 应用场景 | 位置 |
|------|----------|------|
| **Protocol-Oriented** | 所有用例接口 | VoxApplication/UseCases |
| **Factory** | 用例创建 | `UseCaseFactory.swift` |
| **Repository** | 数据访问抽象 | Persistence |
| **MVVM** | 视图逻辑分离 | UIShared/ViewModels |
| **Dependency Injection** | 用例依赖管理 | UseCaseFactory → ViewModels |
| **Observer** | 状态订阅 | @Published, Combine |
| **Strategy** | LLM 提供商切换 | LLMKit/Providers |
| **Command** | 文本编辑操作 | Patch, Checkpoint |

---

## 关键技术决策

### 1. 为什么分成4个包？

**优势**:
- ✅ **编译速度**: 模块化编译，只重新编译修改的包
- ✅ **依赖清晰**: 编译器强制依赖方向，防止循环依赖
- ✅ **团队协作**: 不同团队可独立开发不同包
- ✅ **测试隔离**: 每个包可独立测试
- ✅ **代码复用**: Domain/Infrastructure 可被其他项目复用

**权衡**:
- ⚠️ 初始搭建成本较高
- ⚠️ 包间接口需谨慎设计

### 2. 为什么 Infrastructure 和 Domain 并列？

- **Domain**: 业务规则，与技术无关
- **Infrastructure**: 技术实现，与业务无关
- **Application**: 连接二者，编排业务流程

这是 Clean Architecture 的核心，避免技术细节污染业务逻辑。

### 3. 为什么 Presentation 依赖所有层？

- 最外层负责展示，需要知道所有内容
- 但内层永远不知道 Presentation 的存在
- 保证业务逻辑可独立于 UI 测试和复用

---

## 未来优化方向

### 1. 进一步模块化
- 将 `LLMKit` 拆分为独立的包（可复用于其他项目）
- 将 `DesignSystem` 独立成包

### 2. 依赖注入框架
- 当前使用手动 DI，可考虑引入 Factory/Swinject

### 3. 跨平台扩展
- 当前支持 iOS/macOS，可扩展到 watchOS
- PlatformUI 分别实现各平台特定视图

### 4. 性能优化
- 监控包间依赖深度，避免过度抽象
- 使用 `@_spi` 隐藏内部实现细节

---

## 快速导航

### 添加新功能时应该修改哪里？

| 场景 | 修改位置 |
|------|----------|
| 新增业务实体 | VoxDomain/CoreModels |
| 新增外部服务（如新的LLM） | VoxInfrastructure/LLMKit/Providers |
| 新增业务流程 | VoxApplication/UseCases |
| 新增UI组件 | VoxPresentation/UIShared/Components |
| 新增页面/视图 | VoxPresentation/PlatformUI |
| 修改主题/设计 | VoxPresentation/UIShared/DesignSystem |

---

## 总结

VoxPocket 的包架构体现了：
1. **清晰的职责分离**：每个包有明确的单一职责
2. **严格的依赖控制**：通过 SPM 编译器强制依赖方向
3. **高可测试性**：每层都可独立测试
4. **良好的扩展性**：新功能添加遵循开闭原则

这种架构适合中大型 iOS/macOS 应用，特别是需要复杂业务逻辑、多种外部服务集成、跨平台支持的场景。

# VoxPocket 依赖关系图

## 包级依赖（Package-level Dependencies）

```mermaid
graph TB
    subgraph Presentation["🎨 VoxPresentation<br/>(展示层)"]
        UIShared[UIShared<br/>ViewModels, Components<br/>DesignSystem]
        PlatformUI[PlatformUI<br/>iOS/macOS Views]
    end

    subgraph Application["⚙️ VoxApplication<br/>(应用层)"]
        UseCases[UseCases<br/>Business Logic Flows]
    end

    subgraph Infrastructure["🔧 VoxInfrastructure<br/>(基础设施层)"]
        TranscriptionKit[TranscriptionKit<br/>Speech Recognition]
        LLMKit[LLMKit<br/>LLM Services]
        Persistence[Persistence<br/>Data Storage]
        Observability[Observability<br/>Logging & Monitoring]
        PlatformAdapters[PlatformAdapters<br/>System Integration]
        Preferences[Preferences<br/>User Settings]
    end

    subgraph Domain["💎 VoxDomain<br/>(领域层)"]
        CoreModels[CoreModels<br/>Entities]
        TextHistory[TextHistory<br/>History Management]
    end

    %% Presentation dependencies
    PlatformUI --> UIShared
    UIShared --> UseCases
    UIShared --> CoreModels
    UIShared --> TextHistory
    UIShared --> LLMKit
    UIShared --> TranscriptionKit
    UIShared --> PlatformAdapters
    UIShared --> Preferences
    PlatformUI --> CoreModels
    PlatformUI --> UseCases
    PlatformUI --> PlatformAdapters
    PlatformUI --> Preferences
    PlatformUI --> LLMKit
    PlatformUI --> TranscriptionKit

    %% Application dependencies
    UseCases --> CoreModels
    UseCases --> TextHistory
    UseCases --> TranscriptionKit
    UseCases --> LLMKit
    UseCases --> Persistence
    UseCases --> Observability
    UseCases --> PlatformAdapters

    %% Infrastructure dependencies
    LLMKit --> CoreModels
    LLMKit --> TranscriptionKit
    LLMKit --> Observability
    TranscriptionKit --> CoreModels
    TranscriptionKit --> Observability
    Persistence --> CoreModels
    Persistence --> TextHistory
    Observability --> CoreModels
    PlatformAdapters --> CoreModels
    PlatformAdapters --> Observability

    %% Domain dependencies
    TextHistory --> CoreModels

    %% Styling
    classDef domainStyle fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef infraStyle fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef appStyle fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef presStyle fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px

    class CoreModels,TextHistory domainStyle
    class TranscriptionKit,LLMKit,Persistence,Observability,PlatformAdapters,Preferences infraStyle
    class UseCases appStyle
    class UIShared,PlatformUI presStyle
```

## 模块内部依赖（Module-level Dependencies）

### LLMKit 内部结构

```mermaid
graph LR
    subgraph LLMKit
        Protocols[Protocols<br/>LLMServiceProtocol]
        Models[Models<br/>Request/Response]
        Providers[Providers<br/>OpenAI, Anthropic]
        Services[Services<br/>LLMService]
        Utilities[Utilities<br/>Helpers]
    end

    Services --> Protocols
    Services --> Models
    Providers --> Protocols
    Providers --> Models
    Services --> Providers
    Services --> Utilities

    CoreModels --> Protocols
    Observability --> Services
```

### UIShared 内部结构

```mermaid
graph LR
    subgraph UIShared
        ViewModels[ViewModels<br/>EditorViewModel, etc.]
        Components[Components<br/>Reusable UI]
        DesignSystem[DesignSystem<br/>Theme, Colors, Fonts]
        Views[Views<br/>Shared Views]
        ViewStates[ViewStates<br/>State Models]
        Models[Models<br/>UI Models]
        Snackbar[Snackbar<br/>Notifications]
    end

    ViewModels --> Components
    ViewModels --> ViewStates
    ViewModels --> Models
    Components --> DesignSystem
    Views --> Components
    Views --> DesignSystem
    Snackbar --> DesignSystem

    ViewModels -.UseCases.-> UseCasesExt[UseCases]
    ViewModels -.CoreModels.-> CoreModelsExt[CoreModels]
```

## 用例编排流程（Use Case Orchestration）

### 录音 → 转录 → 精炼流程

```mermaid
sequenceDiagram
    participant UI as EditorViewModel
    participant RC as RecordingUseCase
    participant TC as TranscriptionUseCase
    participant TK as TranscriptionKit
    participant IR as IntentRecognitionUseCase
    participant RF as RefinementUseCase
    participant LLM as LLMKit
    participant PS as Persistence

    UI->>RC: startRecording()
    activate RC
    RC->>TK: startCapture()
    TK-->>RC: Audio Stream
    RC->>TC: transcribe(audio)
    activate TC
    TC->>TK: recognize(audio)
    TK-->>TC: Text Chunks
    TC-->>UI: Transcription Updates
    deactivate TC
    RC->>PS: saveSession()
    deactivate RC

    UI->>IR: recognizeIntent(selectedText)
    activate IR
    IR->>LLM: analyzeIntent()
    LLM-->>IR: Intent (refine/expand/fix)
    deactivate IR

    UI->>RF: refine(text, intent)
    activate RF
    RF->>LLM: generateRefinement()
    LLM-->>RF: Stream Refined Text
    RF->>PS: saveCheckpoint()
    RF-->>UI: Refined Text Updates
    deactivate RF
```

### ViewModel → UseCase → Infrastructure 数据流

```mermaid
graph TD
    subgraph Presentation Layer
        EVM[EditorViewModel]
        RVM[RefinementViewModel]
    end

    subgraph Application Layer
        RecUC[RecordingUseCase]
        TransUC[TranscriptionUseCase]
        IntentUC[IntentRecognitionUseCase]
        RefineUC[RefinementUseCase]
        EditUC[EditingUseCase]
        HistUC[HistoryUseCase]
    end

    subgraph Infrastructure Layer
        TK[TranscriptionKit]
        LLM[LLMKit]
        PS[Persistence]
        OBS[Observability]
    end

    subgraph Domain Layer
        Session[Session Entity]
        Checkpoint[Checkpoint]
        Patch[Patch]
    end

    EVM -->|record| RecUC
    EVM -->|edit| EditUC
    EVM -->|history| HistUC
    RVM -->|refine| RefineUC
    RVM -->|intent| IntentUC

    RecUC --> TK
    TransUC --> TK
    IntentUC --> LLM
    RefineUC --> LLM

    RecUC --> PS
    EditUC --> PS
    RefineUC --> PS

    RecUC --> OBS
    RefineUC --> OBS

    TK -.creates.-> Session
    EditUC -.creates.-> Checkpoint
    RefineUC -.creates.-> Patch

    PS -.stores.-> Session
    PS -.stores.-> Checkpoint
```

## 依赖方向规则

### ✅ 允许的依赖方向

```
Presentation → Application → Infrastructure → Domain
Presentation → Domain (直接依赖实体)
Infrastructure → Domain (技术实现依赖实体)
```

### ❌ 禁止的依赖方向

```
Domain ↛ Infrastructure (领域不知道技术细节)
Domain ↛ Application (领域不知道业务流程)
Infrastructure ↛ Application (技术层不知道业务)
Application ↛ Presentation (用例不知道UI)
```

## 外部依赖

```mermaid
graph LR
    subgraph External
        AsyncAlgo[swift-async-algorithms]
        AppleSpeech[Apple Speech Framework]
        OpenAI[OpenAI API]
        Anthropic[Anthropic API]
    end

    subgraph VoxPocket
        LLMKit
        TranscriptionKit
        Infrastructure
    end

    LLMKit --> AsyncAlgo
    LLMKit --> OpenAI
    LLMKit --> Anthropic
    TranscriptionKit --> AppleSpeech
    Infrastructure --> AsyncAlgo
```

## 编译依赖顺序

基于依赖关系，编译顺序如下：

```
1. VoxDomain (无依赖，最先编译)
   ├─ CoreModels
   └─ TextHistory

2. VoxInfrastructure (依赖 Domain)
   ├─ Observability
   ├─ Preferences
   ├─ TranscriptionKit
   ├─ PlatformAdapters
   ├─ Persistence
   └─ LLMKit

3. VoxApplication (依赖 Domain + Infrastructure)
   └─ UseCases

4. VoxPresentation (依赖所有，最后编译)
   ├─ UIShared
   └─ PlatformUI
```

## 循环依赖检测

当前架构 **无循环依赖**：

- ✅ Domain 完全独立
- ✅ Infrastructure 单向依赖 Domain
- ✅ Application 依赖 Domain + Infrastructure，无反向依赖
- ✅ Presentation 作为最外层，只向内依赖

**如何避免循环依赖**：
1. 使用协议（Protocol）定义接口
2. 依赖注入（Dependency Injection）
3. 观察者模式（Publisher/Subscriber）
4. 事件驱动（Event Bus）

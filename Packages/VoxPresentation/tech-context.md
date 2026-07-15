---
layer: VoxPresentation
role: SwiftUI 视图与 ViewModel —— 展示层,驱动录音/编辑/精炼的用户界面
depends_on: [VoxDomain, VoxInfrastructure, VoxApplication]
depended_by: []
red_lines:
  - 可依赖下层三包(+ 外部 LokiKit);本层是依赖链顶端,不得被任何 layer 依赖(宪法 II)
  - 所有 ViewModel 与 UI 代码 @MainActor;禁止主线程阻塞调用(宪法 III)
  - 转写/精炼文本是用户敏感数据,禁止写入日志或遥测负载(宪法 IV)
  - ViewState 契约用协议;@Published 驱动 SwiftUI,状态更新走不可变副本(宪法 I)
roles:
  Types:   [ViewStates, Models, DesignSystem]
  Runtime: [ViewModels, Snackbar]
  UI:      [Views, Components]
test: swift test --package-path Packages/VoxPresentation
owns: [UIShared, PlatformUI, WidgetUI]
---

# VoxPresentation Tech Context

## 职责
展示层。三个 target:
- **UIShared**:跨平台 ViewModel / Components / DesignSystem / ViewStates / Snackbar / Views。
  `EditorViewModel`(2.5s 静音自动停)、`ViewState` 协议、`@Published` 驱动。
- **PlatformUI**:平台特定视图(iOS/macOS),依赖 UIShared。
- **WidgetUI**(dynamic library):独立无依赖。

## 依赖
- **仓库内**:`VoxDomain` + `VoxInfrastructure` + `VoxApplication`(UseCases)。
- **外部**:`LokiKit`(遥测)。

## 约束 / 红线投影
- **@MainActor**:全部 ViewModel 与 UI。
- **隐私**:UI 层持有用户文本用于展示;绝不落日志/遥测。
- **状态**:`ViewState` 协议定义 view-model 契约;`@Published` 更新走不可变值。

## 层内轴
`Types(ViewStates/Models/DesignSystem)` ← `Runtime(ViewModels/Snackbar)` ← `UI(Views/Components)`。
`DesignSystem`(token,Types 角色)不得 import `Views`;`Views` 依赖 token 合法。

# Design System: Theme + Tokens + SwiftUI Modifier 方案

日期：2026-02-03

## 目标
建立一个轻量设计系统，统一字体与颜色，并支持浅色/深色双主题。开发体验保持 SwiftUI 原有调用习惯（例如 `.foregroundColor(...)`、`.font(...)`），但参数改为语义化 token。

## 核心方案
### Theme 结构
- `Theme` 负责将 token 映射为具体的 `Color`/`Font`。
- `Theme` 提供浅色/深色版本，并通过 `ColorScheme` 自动选择。
- 结构建议：
  - `Theme.Palette`：颜色令牌集合
  - `Theme.Typography`：字体令牌集合

### Token 类型
- `enum ColorToken`：
  - 文本：`textPrimary` / `textSecondary` / `textTertiary`
  - 玻璃/表面：`surfaceGlass` / `surfaceGlassStrong` / `surfaceElevated`
  - 边界：`strokeSubtle` / `strokeStrong`
  - 交互：`accentPrimary` / `accentSecondary`
  - 状态：`statusListening` / `statusRefining` / `statusDone` / `statusError`
  - 背景：`backgroundBase` / `backgroundVignette`
- `enum FontToken`：`title` / `headline` / `body` / `callout` / `caption`

### View Modifier（保持原有 API 习惯）
在 `extension View` 中提供同名重载：
- `foregroundColor(_ token: ColorToken)`
- `font(_ token: FontToken)`

内部通过 `@Environment(\.colorScheme)` 选择 `Theme.current(scheme)`，并根据 token 返回具体颜色/字体。

### 字体策略
- 统一使用系统字体（SF Pro），确保 iOS/macOS 质感一致。
- 字体风格可选 `design: .rounded` 或 `.default`，与液态玻璃气质匹配。

## 使用示例（目标写法）
- `.foregroundColor(.textPrimary)`
- `.font(.title)`
- `.foregroundColor(.statusListening)`

## 影响范围
- 先覆盖 HomeRecorderView 与 BackgroundAtmosphere（以及相关子组件）。
- 后续可逐步替换整个 UIShared 中的硬编码颜色/字体。

## 测试 / 验证
- 主要为手动预览验证：
  - 浅色/深色模式切换
  - 状态色在不同背景下的对比度
  - 字体层级与整体阅读性

# Apple UI Testing 工具套件 — 上下文文档

> 加载此文档即可恢复任务状态，无需重新阅读历史对话。
> 最后更新：2026-04-01（session 3）

---

## 任务背景

为所有 iOS/macOS app 构建一套通用的 UI 自动化测试工具，包含三个组件：

1. **MCP Server** (`apple-ui-tester`) — 让 Claude Agent 通过工具调用控制模拟器
2. **Claude Code Skill** (`apple-ui-testing`) — 教 Agent 标准测试工作流
3. **AppleUITesting SPM Package** — 嵌入 app 的测试辅助库

---

## 组件状态

### 1. MCP Server ✅ 完成并已注册

**位置**：`~/.claude/mcp-servers/apple-ui-tester/`

**注册**：`~/.claude/mcp.json` 中已添加：
```json
"apple-ui-tester": {
  "type": "stdio",
  "command": "node",
  "args": ["/Users/tianpli/.claude/mcp-servers/apple-ui-tester/dist/index.js"],
  "env": { "ANTHROPIC_API_KEY": "${ANTHROPIC_API_KEY}" }
}
```

**构建**：已编译，入口 `dist/index.js`

**12 个工具**：

| 工具 | 功能 |
|------|------|
| `list_simulators` | 列出所有模拟器及状态 |
| `boot_simulator` | 启动模拟器 |
| `launch_app` | 打开 app |
| `terminate_app` | 关闭 app |
| `take_screenshot` | 截图（返回 base64 PNG） |
| `get_ax_tree` | 获取无障碍树（需 UITestingBridge） |
| `tap_element` | 点击（归一化坐标 0.0–1.0） |
| `swipe` | 滑动手势 |
| `evaluate_screenshot` | 用 Claude Vision 评估截图 |
| `run_xcuitest` | 运行 XCUITest suite |
| `get_app_info` | 获取 app bundle 信息 |
| `set_simulator_ui` | 切换深色/浅色模式 |

**关键源文件**：
- `src/drivers/simctl.ts` — xcrun simctl 封装
- `src/tools/evaluateScreenshot.ts` — 调用 `claude-sonnet-4-6` Vision API
- `src/tools/getAxTree.ts` — 查询 `http://127.0.0.1:7979/ax-tree`
- `src/index.ts` — MCP stdio server 入口

**重启 Claude Code 后**自动生效（已注册到 `mcp.json`）。

---

### 2. Skill ✅ 完成

**位置**：`~/.claude/skills/apple-ui-testing.md`

调用方式：用户输入 `/apple-ui-testing` 即可激活标准工作流：
1. 找/启动模拟器
2. 启动 app
3. 截图 + 评估初始状态
4. 交互操作
5. 汇报结果（通过/失败、截图、建议）

---

### 3. AppleUITesting SPM Package ✅ 完成

**位置**：`/Users/tianpli/Development/AppleUITesting/`
**状态**：`swift build` ✅，`swift test` ✅（7 tests passed）
**Git**：已初始化，已提交到 `main`

**Package.swift 平台要求**：iOS 17+，macOS 14+

**五个 Library Target**：

#### AccessibilityKit
```
Sources/AccessibilityKit/
├── AccessibilityID.swift          # 类型化的无障碍 ID（RawRepresentable, Hashable）
├── ViewModifiers.swift            # .accessibilityId(_:) SwiftUI 修饰符
└── XCUIQuery+Extensions.swift     # XCUIApplication.element/button/textField(id:)
```
用法：
```swift
import AccessibilityKit
// 标记视图
Button("录音").accessibilityId("vox.record.button")
// XCUITest 查询
let btn = app.button(id: "vox.record.button")
```

#### SnapshotKit
```
Sources/SnapshotKit/
├── SnapshotConfiguration.swift    # 设备预设（iPhone15Pro, iPadPro11, MacBook16...）
└── SnapshotHelpers.swift          # assertAppSnapshot(_:on:) 封装
```
用法（测试文件中）：
```swift
import SnapshotKit
@MainActor func testRecordScreen() {
    assertAppSnapshot(RecordView(), on: .iPhone15Pro)
}
```
依赖：`swift-snapshot-testing 1.17.0+`（pointfreeco）

#### PerformanceKit
```
Sources/PerformanceKit/
├── FrameTracker.swift             # CADisplayLink 帧率追踪，FrameMetrics 计算
└── PerformanceAssertions.swift    # assertSmoothAnimation / assertNoJank
```
用法：
```swift
import PerformanceKit
let tracker = FrameTracker()
tracker.start()
// ... 触发动画 ...
let metrics = tracker.stop()
assertSmoothAnimation(metrics, minimumFPS: 55)
assertNoJank(metrics, maxRatio: 0.05)
```

#### VisionEvalKit
```
Sources/VisionEvalKit/
├── EvalExpectation.swift          # EvalExpectation, EvalResult, EvalReport
├── VisionEvaluator.swift          # 调用 Anthropic API (claude-sonnet-4-6)
└── ScreenCapture.swift            # captureScreen() — ScreenCaptureKit (macOS) / UIScreen (iOS)
```
用法：
```swift
import VisionEvalKit
let evaluator = VisionEvaluator() // 从 ANTHROPIC_API_KEY 读取密钥
let imageData = try await captureScreen()
let report = try await evaluator.evaluate(
    imageData: imageData,
    sceneName: "录音界面",
    expectations: [
        EvalExpectation("录音按钮可见"),
        EvalExpectation("无错误弹窗"),
    ]
)
print(report.summary())
```

#### UITestingBridge
```
Sources/UITestingBridge/
└── UITestingBridge.swift          # GCD HTTP server，监听 7979 端口
```
在 app debug 入口启动：
```swift
#if DEBUG
UITestingBridge.start()  // 暴露 /ax-tree 和 /health
#endif
```
启动后 MCP 的 `get_ax_tree` 工具即可读取 app 的完整无障碍树。

---

## 已知问题 / SourceKit 误报

以下 SourceKit 报错是**误报**，实际 `swift build` 通过：
- `Package.swift` 中 "No such module 'PackageDescription'" — IDE 未索引到 PackageDescription
- `ViewModifiers.swift` 中 "Cannot find type 'AccessibilityID'" — 跨文件引用的 SourceKit bug
- `UITestingBridge.swift` 中 AX API 找不到 — 需要 ApplicationServices framework，运行时正确链接
- `ScreenCapture.swift` 中 `CGWindowListCreateImage` 警告 — 已移除该调用

---

## 待续任务

### 高优先级

1. ~~**将 AppleUITesting 发布到 GitHub**~~ ✅ 完成
   - 仓库：`https://github.com/LeePepe/AppleUITesting`
   - Skill 文件 SPM URL 已更新

2. ~~**在 VoxPocket 中集成 UITestingBridge**~~ ✅ 完成
   - `project.pbxproj` 已添加本地包引用 (`../../AppleUITesting`) 及产品依赖
   - `VoxPocketApp.swift` `init()` 中已添加 `#if DEBUG UITestingBridge.start() #endif`
   - `xcodebuild` BUILD SUCCEEDED，已提交 `main`

3. ~~**UITestingBridge 修复与验证**~~ ✅ 完成（session 3）
   - **根本原因**：App Sandbox 的 `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO` 阻止端口绑定
   - **修复**：`project.pbxproj` Debug 配置改为 `ENABLE_INCOMING_NETWORK_CONNECTIONS = YES`
   - **注意**：Xcode 用 `ENABLE_INCOMING_NETWORK_CONNECTIONS` 生成 entitlements，直接编辑 `.entitlements` 文件无效
   - `curl http://localhost:7979/health` → `{"status":"ok"}` ✅
   - `curl http://localhost:7979/ax-tree` → 完整 AX 树 ✅
   - 已提交 `main`（`c6778e9`）

4. ~~**AX 标识符改善**~~ ✅ 完成（session 4）
   - `VoxPocketRootView.swift` splitViewShell toolbar 三个按钮补全 `accessibilityIdentifier`
   - commit `0d93f93`，build ✅，review ✅

5. **用 MCP 工具测试 VoxPocket** ← **下一步从这里继续**
   - MCP server (`apple-ui-tester`) 本身正常，但需要重启 Claude Code 才能在会话中加载工具
   - 重启后，`apple-ui-tester` 的 12 个工具应出现在 deferred tools 中
   - 测试流程：`take_screenshot` → `evaluate_screenshot` → `get_ax_tree` → 报告

   **AX 覆盖率现状**（已验证）：
   | 标识符 | 角色 | 状态 |
   |--------|------|------|
   | `vox.record.button` | AXButton | ✅ |
   | `vox.transcript.final` | AXStaticText | ✅ |
   | `vox.transcript.live` | AXStaticText | ✅ |
   | `vox.editor.undo` | AXButton | ✅ （iPhone + iPad/Mac） |
   | `vox.editor.redo` | AXButton | ✅ （iPhone + iPad/Mac） |
   | `vox.editor.refine.toggle` | AXButton | ✅ （iPhone + iPad/Mac） |

### 低优先级

4. **SnapshotKit iOS 支持验证** — 目前 macOS 路径测试通过，iOS 路径仅编译验证
5. **UITestingBridge iOS AX Tree** — 当前 iOS 实现返回浅层节点，可深化递归

---

## 架构图

```
Claude Agent
    │
    ├── 调用 MCP 工具 (apple-ui-tester)
    │       │
    │       ├── xcrun simctl ──→ iOS Simulator
    │       ├── ScreenCaptureKit ──→ 截图
    │       ├── Claude Vision API ──→ 评估截图
    │       └── HTTP :7979 ──→ UITestingBridge (在 app 内)
    │
    └── 使用 Skill (apple-ui-testing.md)
            └── 标准工作流指南

iOS/macOS App (集成 AppleUITesting SPM)
    ├── AccessibilityKit — 标记 UI 元素
    ├── SnapshotKit — 视觉回归测试
    ├── PerformanceKit — 帧率/卡顿检测
    ├── VisionEvalKit — AI 截图评估
    └── UITestingBridge — 暴露 AX 树给 MCP
```

---

## 关键文件路径速查

```
~/.claude/mcp.json                                          # MCP 注册（apple-ui-tester 已加）
~/.claude/mcp-servers/apple-ui-tester/                     # MCP server 源码
~/.claude/mcp-servers/apple-ui-tester/dist/index.js        # 编译产物（入口）
~/.claude/skills/apple-ui-testing.md                       # Skill 文件

/Users/tianpli/Development/AppleUITesting/                 # 通用 SPM 包根目录
/Users/tianpli/Development/AppleUITesting/Package.swift    # 包配置
/Users/tianpli/Development/VoxPocket/                      # VoxPocket 项目根目录
```

---

## 恢复任务的第一步

重启后，直接告诉 Claude：

> "继续 Apple UI Testing 工具套件任务，参考 CONTEXT_apple_ui_testing.md"

Claude 会从**待续任务 #3**（MCP 工具测试 VoxPocket）开始继续。

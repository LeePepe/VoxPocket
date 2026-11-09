# VoxPocket iOS 2.0 Todo-First Redesign Specification (`spec.md`)

- **Feature ID**: `013-ios-todo-redesign`
- **Stage**: Phase 1 — Product & Functional Specification (Approved Direct Execution)
- **Target Platform**: `mobile` (iOS 26+ / iPhone Action Button + Dynamic Island Live Activity)
- **Repository**: `VoxPocket`
- **Status**: Approved & Frozen (Owner direct mandate 2026-11-09)

---

## 1. 核心功能定位

本次迭代聚焦 `VoxPocket` **iOS 端** 的全面重设计与落地，遵循 `L0 -> L1 -> L2` 渐进式披露规范、呼吸感 5 抓手与零猜测法则（`说法 · 入口 · 反馈`）：

1. **主界面聚焦 Todo 展示（Todo-First Workspace）**：
   - iOS 启动后的核心主场直接挂载 `IOSCleanSlateWorkspaceView`（以清爽、高呼吸感的待办清单为唯一视觉重心，同时保留 UI 测试的录音控制 `accessibilityIdentifier`）。
   - 单屏严格控制在 `<= 2–3` 个视觉容器块：顶部紧凑状态筛选条（`全部 / 待处理 / AI 执行中 / 已完成`）+ 中部高呼吸感无框色阶待办清单（支持点按勾选完成、查看详情 Sheet、工具栏呼出最近语音速记 Sheet）+ 底部 Liquid Glass 悬浮录音坞。
2. **支持 iPhone Action Button（操作按钮）快速录音**：
   - 强化 `StartRecordingIntent`（及 Shortcuts / Control Center 控件）与 `VoxCaptureLiveActivity`（灵动岛 / 锁屏实时活动）：一键触发极速语音录入，自动根据用户在设置中选定的默认去向启动对应模式的录音，并实时联动声波动画与计时反馈。
   - 在 `VoxPocketWidgetBundle` 中正式挂载 `VoxCaptureLiveActivity`（iOS），确保灵动岛与实时状态反馈在系统级闭环。
3. **录音去向可在 Settings 切换（零猜测大白话配置）**：
   - 新增持久化偏好键 `PreferencesKey.iosQuickCaptureDestination`（对应 `CaptureMode`：`.todo`「直接存入待办」或 `.text`「自动复制到剪贴板」，默认 `.todo` 以契合 Todo 主场定位，并可在设置与底部录音坞实时双向同步）。
   - 设置页使用零猜测大白话表达意图：**「录音完成后去向」** → **「直接存入待办」**（自动提炼标题并加入待办清单） vs. **「自动复制到剪贴板」**（润色为干净文字并复制，方便直接粘贴）。
4. **零猜测确定性反馈回执（`说法 · 入口 · 反馈`）**：
   - 录音并转写/提炼完成后，立即在底部录音坞上方给出明确去向回执胶囊（伴随 `SensoryFeedback.success` 与 `.contentTransition(.numericText())`）：
     - 存入 Todo 时显示：**「已存入待办 · <待办标题摘要>」**
     - 复制到剪贴板时显示：**「已复制到剪贴板 · 可直接粘贴」**（并在 iOS 端自动写入 `UIPasteboard.general.string`）。

---

## 2. 架构与分层边界（遵守 `AGENTS.md` 与 `tech-context.md`）

| Layer | 变更范围 (`Owned Paths`) | 职责与红线 |
|---|---|---|
| `VoxInfrastructure` (`Preferences`) | `Packages/VoxInfrastructure/Sources/Preferences/PreferencesStore.swift` | 新增 `iosQuickCaptureDestination` 偏好键与变更通知，严禁引入高层依赖。 |
| `VoxPresentation` (`UIShared`, `WidgetUI`) | `Packages/VoxPresentation/Sources/UIShared/**`, `Packages/VoxPresentation/Sources/WidgetUI/**`, `Packages/VoxPresentation/Tests/**` | 实现 `AppTheme.swift`（`<80` 行，`VS-003 × VS-005` 呼吸感色阶与间距）、重构 `IOSCleanSlateWorkspaceView.swift`（Todo 主场、呼吸感 5 抓手、底部 Liquid Glass 录音坞、大白话 Settings Sheet、确定性去向回执）、更新 `VoxWorkspaceViewModel.swift`（持久化默认去向、完成回执文案、勾选完成动作）及 `VoxCaptureLiveActivity.swift`。 |
| `VoxPocketApp` | `VoxPocket/VoxPocket/ContentView.swift`, `VoxPocket/VoxPocket/Intents/StartRecordingIntent.swift`, `VoxPocket/VoxPocket/ServiceContainer.swift`, `VoxPocket/VoxPocket/Localizable.xcstrings`, `VoxPocketWidget/VoxPocketWidgetBundle.swift`, `VoxPocket/VoxPocketUITests/VoxPocketUITests.swift` | iOS `ContentView` 切换至 Todo 主场工作台并桥接 `StartRecordingIntent` / DeepLink / 剪贴板复制回调；更新双语 `Localizable.xcstrings`（`en`, `zh-Hans`）。 |

---

## 3. Obsolete Test Manifest & Deprecated Test Clauses

根据 Spec-First 规则，记录因 iOS 主界面升级为 Todo-First 工作台而需对齐的测试断言：
- `VoxPocket/VoxPocketUITests/VoxPocketUITests.swift:41-50` & `92-109`：原 UI 测试断言 `vox.record.button` 与 `vox.stop.button` 存在且可点击切换。在新版 `IOSCleanSlateWorkspaceView` 的底部主录音按钮上保留 `accessibilityIdentifier(viewModel.isRecordingActive ? "vox.stop.button" : "vox.record.button")`，并在列表容器保留 `vox.session.list`，确保 UI 自动化测试无缝通过。
- `Packages/VoxPresentation/Tests/UISharedTests/VoxWorkspaceContractTests.swift`：扩充覆盖录音去向切换（Todo vs. 剪贴板）、确定性回执文案（`已存入待办` / `已复制到剪贴板`）、勾选完成待办与 Action Button DeepLink 默认去向路由测试。

---

## 4. 验收标准（Acceptance Criteria）

1. `python3 scripts/verify_design_cases.py audit-code --platform mobile --path Packages/VoxPresentation/Sources/UIShared/Views/IOSCleanSlateWorkspaceView.swift` 0 findings 通过；
2. `python3 scripts/verify_design_cases.py audit-l10n --path VoxPocket/VoxPocket --locales en,zh-Hans` 0 findings 通过；
3. `scripts/verify` 全部层门禁通过；
4. iOS 模拟器构建并截取 Light / Dark 模式主界面（Todo 主场）、录音态、Settings（录音去向切换 + Action Button 引导）真实截图，视觉与对齐检查无遮挡/截断；
5. Owner 授权开启 `.github/workflows/testflight.yml` 的 `ios` TestFlight 手动发布分支并更新对应门禁测试。


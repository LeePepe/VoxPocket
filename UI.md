# Voice-to-Text App UI 逻辑总览

定位：一切通过语音完成（说话 → 生成/优化文本 → 复制/插入）。

- 不提供 Editor（不做手动编辑/对比/选择 refine 类型）
- 主页面极简：文本 + 语音条 + refine 条 + Stop/Restart/New Session + Undo/Redo
- iPhone 用抽屉“侧边栏”展示 History
- Profile + Settings 合并为 Me 页面

---

## 0. 概念模型（Session / Segment / Stack）

- Session：一条记录（对应 History 里的一项）
  - 包含 `rawText`（原始转写累积）与 `refinedText`（优化文本累积）
  - 包含 `segments[]`（每次“提交”的语音片段/优化结果作为一个 segment）
- Segment：一次“可撤销”的变更单元
  - 例：新增一段 raw、一次 refine 覆盖、一次语音纠错指令导致的修改
- Undo/Redo：作用于 segment 栈
  - `past[]`（已提交） / `current` / `future[]`（撤销后的可重做）

关键策略：用户只要停留在主页面，就继续当前 Session（append）。真正“开始新的一条记录”必须点击 New Session。

---

## 1. 顶层导航（iPhone / iPad / macOS）

### 1.1 iPhone（无 Tab，抽屉侧边栏）

```
AppRootView
└─ iPhoneShellView
   └─ DrawerSplitContainer (左侧抽屉 + 主内容)
      ├─ SidebarDrawerView   (History + Me 入口)
      └─ MainNavigationStack
         ├─ HomeRecorderView (默认根页面)
         └─ MeRootView       (Profile + Settings)
```

用户流：

- 默认进入 Home
- ☰ 打开抽屉：看到 History
- 点某条 History：收起抽屉 → Home 切换到对应 Session（继续语音追加/优化）
- 点 Me：收起抽屉 → push 到 Me

### 1.2 iPad / macOS（可用 SplitView）

```
RootContainer
└─ NavigationSplitView
   ├─ Sidebar: History + Me
   └─ Detail: Home / Me（根据选择切换）
```

iPad/mac 侧边栏可以常驻；iPhone 用抽屉实现“侧边栏体验”。

---

## 2. Sidebar（侧边栏）= History（iPhone 抽屉 / iPad/mac 常驻）

```
SidebarDrawerView
├─ SidebarHeader
│  ├─ AppMiniBrand / Status (录音中🔴、可选：模型 badge)
│  └─ Close (iPhone 可选：点遮罩关闭)
│
├─ HistorySearchBar
├─ HistoryFilterRow (可选：All / Starred)
│
├─ HistoryList
│  └─ HistoryRow
│     ├─ SummaryText (refined 前 1 行)
│     ├─ MetaLine (time · duration · status)
│     └─ StarToggle / ContextMenu (可选)
│
└─ SidebarFooter
   ├─ MeEntryRow (Avatar + "Me")
   └─ (Optional) QuickActions: Export / Logs
```

History 点击行为（重要）：

- 不进入 Editor（因为不存在）
- 行为：`select(sessionID)` → Home 切换当前 session（并可自动滚到末尾）

---

## 3. HomeRecorderView（主页面：极简且语音驱动）

### 3.1 主页职责

- 展示 Refined 文本（主输出）
- 展示 SpeechBar（录音/识别状态）
- 展示 RefineBar（优化状态/重试）
- 通过语音指令做纠错与改写（无需编辑 UI）
- 提供 Undo/Redo 与 Stop/Restart/New Session

### 3.2 View 层级

```
HomeRecorderView
├─ TopBar
│  ├─ SidebarToggleButton (☰)
│  ├─ UndoButton (↶)
│  ├─ RedoButton (↷)
│  ├─ Spacer
│  └─ RawTextEntryButton (Raw，右上角原始文本入口)
│
├─ RefinedTextPane (主输出，大字号，可选择/滚动/长按复制)
│  └─ StatusLine (Listening / Transcribing / Refining / Done / Error)
│
├─ SpeechBar (语音条)
│  ├─ WaveformView (极简音量条)
│  └─ MicStatusPill (可选：权限/输入设备)
│
├─ RefineBar (refine 条)
│  ├─ ProgressIndicator
│  └─ RetryHint (失败时：Tap to retry)
│
└─ BottomControls
   ├─ StopButton
   ├─ RestartButton (继续说 / 重录当前段；仍在当前 Session)
   └─ NewSessionButton (封存当前 → 新建 session)
```

### 3.3 macOS 主页差异（上下展示 Raw/Refined）

```
HomeRecorderView_mac
├─ TopBar (☰ / Undo / Redo / Copy 可选)
├─ RefinedTextPane (top)
├─ Divider (可选：可拖拽调整高度)
├─ RawTextPane (bottom)
├─ SpeechBar
├─ RefineBar
└─ BottomControls (Stop / Restart / New Session)
```

mac 上无需 Raw 入口跳转；iPhone 上用右上角 Raw 入口进入 Raw View。

---

## 4. RawTranscriptView（原始文本入口）

iPhone 右上角 Raw 进入；用于“看原始转写”，必要时可做最小交互（复制/搜索）。

```
RawTranscriptView
├─ RawTextPane (只读为主；可选：允许轻量编辑)
├─ (Optional) SegmentTimeline (按段落/时间戳)
└─ Actions
   ├─ Copy
   └─ Close/Back
```

建议默认只读：保证“全部通过语音完成”的一致性；编辑能力可以放到后期。

---

## 5. 状态机（避免 UI 乱跳）

### 5.1 最小状态集

- Idle / Listening / Transcribing / Refining / Done / Error

### 5.2 状态流转（主流程）

```
Idle
 └─ tap Record / voice hotkey
     ↓
Listening
 ├─ silence timeout / tap Stop → Transcribing
 ├─ tap Restart → Idle (清掉本段缓存，但不新建 session)
 └─ tap New Session → Idle (封存当前并新建)

Transcribing
 ├─ success → Refining
 └─ failure → Error(STT)

Refining
 ├─ success → Done
 ├─ failure → Error(Refine)
 └─ tap Stop → Done (保留当前已有 raw/refined)

Done
 ├─ tap Record → Listening (继续追加到当前 Session)
 ├─ tap Restart → Idle (重录下一段，仍在当前 Session)
 └─ tap New Session → Idle (封存当前并新建)

Error
 ├─ retry → 回到上一步（Transcribing/Refining）
 └─ New Session → Idle
```

### 5.3 Undo/Redo 行为（与状态结合）

- Undo/Redo 作用于 Segment 栈
  - Undo：回退最近一次“提交”的变更
  - Redo：恢复 Undo 过的变更
- 可用性建议
  - UndoButton：`past` 非空启用
  - RedoButton：`future` 非空启用
  - Listening/Refining 中：建议先 Stop 再 Undo（按钮可直接触发 Stop → Undo 的组合动作）

---

## 6. 自动停止策略（提升巨大，放到 Me 设置）

- 静音 N 秒自动 Stop：默认 2s，范围 1~5s
- 或 VAD 阈值：更智能（高级开关）
- Listening → 自动进入 Transcribing（无需弹窗）

---

## 7. 错误兜底（必须）

### 7.1 STT 失败（Error(STT)）

- UI：StatusLine 显示「识别失败」
- 操作：
  - Retry Transcribing
  - 保留录音（如果有）/ 保留 raw 已识别部分

### 7.2 Refine 失败（Error(Refine)）

- UI：RefineBar 显示「Tap to retry」
- 操作：
  - Retry Refine
  - 放弃 refine：保留 raw 或已有 refined

---

## 8. Me（Profile + Settings 合并页）

```
MeRootView
└─ MeOverviewView (ScrollView)
   ├─ ProfileCard
   │  ├─ Avatar / DisplayName
   │  ├─ AccountStatusBadge
   │  └─ ProviderRows (ChatGPT / Claude 连接管理)
   │
   ├─ BehaviorCard (核心行为设置)
   │  ├─ AutoStopSilenceSeconds (1~5s)
   │  ├─ VADAdvancedToggle (可选)
   │  ├─ AutoSaveToggle (默认开)
   │  └─ StreamingToggle (可选)
   │
   ├─ PrivacyAndDataCard
   │  ├─ DataRetentionPicker (7/30/Forever)
   │  ├─ ExportDataRow
   │  └─ ClearHistoryRow (danger)
   │
   ├─ DiagnosticsCard
   │  ├─ LoggerLevelRow
   │  ├─ ShareLogsRow
   │  └─ ResetAllSettingsRow (danger)
   │
   └─ AboutCard
      ├─ VersionRow
      ├─ PrivacyPolicyRow
      └─ FeedbackRow
```

---

## 9. 路由与行为对照（实现 mental model）

HomeRecorderView：

- Stop：结束当前段录音/流程（按状态）
- Restart：清本段缓存、准备重录（仍在当前 Session）
- New Session：封存当前 Session → 创建新 Session → 清空 UI
- Undo/Redo：对 Segment 栈操作
- Raw：打开 RawTranscriptView

SidebarDrawerView：

- select history：Home 切换到该 Session（不跳转到 Editor）
- Me：push MeRootView

---

## 10. 可选但建议保留的“隐形能力”（不增加主 UI 复杂度）

- 长按 RefinedTextPane → Copy（默认一键复制方案）
- 后台恢复：来电/锁屏/切后台后恢复到一致状态（不丢 session、不重复提交）
- 安全策略：避免在敏感上下文（如密码输入）触发自动插入（主要对 macOS）

---

## 11. Snackbar 通知组件

### 11.1 设计定位

轻量级、非阻塞式的全局通知机制，用于向用户提供即时反馈。

### 11.2 视觉规范

```
SnackbarContainer (全局，覆盖在所有内容之上)
└─ SnackbarView
   ├─ IconView (可选：类型图标)
   ├─ MessageLabel (主消息文本)
   └─ ActionButton (可选：操作按钮，如"重试"、"撤销")
```

位置与布局：
- iPhone：底部安全区上方，水平居中，左右留边距 16pt
- iPad/macOS：底部偏右，距离右边缘 24pt
- 圆角：12pt
- 高度：自适应内容，最小 48pt
- 最大宽度：iPhone 屏幕宽度 - 32pt，iPad/macOS 固定 400pt

### 11.3 类型与样式

| 类型    | 背景色          | 图标        | 文字色  |
|---------|-----------------|-------------|---------|
| info    | secondarySystem | info.circle | primary |
| success | green/10%       | checkmark   | green   |
| warning | orange/10%      | exclamation | orange  |
| error   | red/10%         | xmark       | red     |

### 11.4 动画与时序

- 入场动画：从底部滑入 + 淡入，时长 0.25s，easeOut
- 退场动画：向下滑出 + 淡出，时长 0.2s，easeIn
- 默认显示时长：3 秒
- 可配置时长范围：1.5s ~ 10s，或永久显示（需用户手动关闭）
- 队列策略：新通知入队，当前通知播放完毕后显示下一条
- 高优先级通知：立即替换当前显示的通知

### 11.5 交互行为

- 点击 Snackbar 主体：关闭当前通知
- 点击 ActionButton：执行关联操作并关闭
- 向下滑动：手势关闭
- 多条通知：排队显示，不堆叠

### 11.6 使用场景示例

| 场景             | 类型    | 消息文本           | 操作按钮 |
|------------------|---------|-------------------|----------|
| 文本已复制       | success | "已复制到剪贴板"   | -        |
| Session 已保存   | success | "Session 已保存"   | -        |
| 同步完成         | info    | "已同步到 iCloud"  | -        |
| 网络错误         | error   | "网络连接失败"     | 重试     |
| 识别失败         | error   | "语音识别失败"     | 重试     |
| Refine 失败      | warning | "优化失败"         | 重试     |
| 权限不足         | warning | "需要麦克风权限"   | 设置     |

### 11.7 与现有 UI 的整合

```
VoxPocketRootView
├─ ... (现有视图层级)
└─ SnackbarContainer (overlay，z-index 最高)
   └─ SnackbarView (当有通知时显示)
```

Snackbar 不应遮挡关键操作区域：
- 当 SpeechBar 活跃时，Snackbar 位置上移避让
- 当键盘弹出时，Snackbar 跟随键盘上移

---

## 12. 明确移除项（保证极简一致性）

- 不做 Editor / 对比页 / 手动选择 refine 类型
- 不在主页面提供复杂的模型/风格选择入口
- 不在主页面做历史管理（删除/导出等放到侧边栏或 Me）

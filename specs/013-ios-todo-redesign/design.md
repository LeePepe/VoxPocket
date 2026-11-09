# VoxPocket iOS 2.0 Todo-First UI/UX Design Specification (`design.md`)

- **Feature ID**: `013-ios-todo-redesign`
- **Version**: `2.0`
- **Upstream Spec**: `specs/013-ios-todo-redesign/spec.md`
- **Design Lead Skill**: `my-designer` (`L0 -> L1 -> L2`) + `visual-design-modernization` + `design-studio`
- **Baseline Gate**: **Plan A (Apple 5 HIG Lenses)** + Localization Gate (`en`, `zh-Hans`) + **Plan C (`DC-001`, `DC-002`)**

---

## 1. L0 Topology & Style Recipe Lock (`appearance-ledger.md`)

| Dimension | Selection | Rationale |
|---|---|---|
| **Platform** | `mobile` (iOS 26+ iPhone Compact & Wide-Touch) | 随身单手 Todo 主场 + Action Button 极速语音录入 + 灵动岛反馈。 |
| **Active Dimensions** | `visual-style` (`VS`), `layout-navigation` (`LN`), `motion-interaction` (`MI`), `typography-copy` (`TC`) | 经 `verify_design_cases.py route` 披露 `appearance-ledger.md`、`interaction-layering.md` 与 `breathing-and-clarity.md`。 |
| **Style Archetype** | `VS-003` (Precision Acoustic Studio) × `VS-005` (Zen Paper Checklist) | 结合 `Things 3` 呼吸感无框纸感待办清单与 `VoxPocket` 精密声学胶囊录音坞。 |
| **Palette (`CL-*`)** | System Semantic Luminance Tiers (`L0` `systemGroupedBackground` -> `L1` `secondarySystemGroupedBackground` -> `L2` `tertiarySystemGroupedBackground`) + `Color.accentColor` / `.orange` / `.red` / `.green` | 严守 90/10 色彩克制与零硬编码 Hex 规则，Light/Dark 双模式自适应对比度 `>= 4.5:1`。 |
| **`surface_mode` & `motion_tier`** | `Operate` · `M1` + `M2` | `AppTheme.snappySpring` (`response: 0.26, dampingFraction: 1.0`) 零弹跳高频切换，手势展开使用 `gestureSpring` (`response: 0.32, dampingFraction: 0.80`)，支持 Reduce Motion 降级。 |

---

## 2. X-Y-Z 三轴交互分层（`interaction-layering.md` · 单屏 `<= 3` 个视觉块）

### Axis X · `Role × Frequency Priority (P0..P3)` 矩阵

| Priority | 1. `Display Only` | 2. `Action Only` | 3. `Display + Action` |
|---|---|---|---|
| **`P0` · Primary Focal** | 待办清单主标题与待处理计数徽标 | 底部悬浮主录音按钮（Action Button 同款一键启停） | **Todo 核心清单行**（点按圆圈完成 + 点按行编辑详情） |
| **`P1` · Inline Companion** | 录音完成后的去向回执胶囊（`已存入待办` / `已复制到剪贴板`）、实时录音计时与声波条 | 状态筛选胶囊条（`待处理 / 全部 / AI 执行中 / 已完成`） | 底部录音坞内的去向快切胶囊（`存入待办 ⇄ 复制文字`） |
| **`P2` · Collapsed Context** | 已完成 Todo 的弱化删除线态、匹配项目胶囊标签 | 右上角「语音速记」入口按钮（折叠纯文本速记历史至按需 Sheet） | 搜索框（`.searchable` 下拉按需展现） |
| **`P3` · On-Demand Drill-Down** | 原始转写对照文本、Action Button 绑定步骤说明 | 右上角「设置」按钮、删除/重试操作 | **设置 Sheet**（配置默认录音去向）与 **Todo 详情编辑 Sheet** |

### Axis Y · 空间折叠与分块上限（`<= 3` Visual Container Groups）
整个 iOS 主屏严禁超过 3 个视觉容器组（彻底杜绝 `DC-001` 平铺堆砌与 `DC-002` 重复数据）：
1. **Group 1 · 顶部紧凑概览与筛选条（`Overview & Filter`）**：一行轻量化状态筛选胶囊（`待处理`、`全部`、`执行中`、`已完成`），带 `.monospacedDigit()` 实时计数。
2. **Group 2 · 高呼吸感 Todo 核心主场（`Primary Stage`）**：以无框色阶卡片承载每条 `VoiceTodo`，次要的纯文字速记历史收纳进顶部工具栏的「速记」按需 Sheet，不再用底部双 Tab 抢占底部录音坞空间。
3. **Group 3 · 底部 Liquid Glass 悬浮录音坞（`Functional Capture Dock`）**：单一 `.safeAreaInset(edge: .bottom)` 承载确定性回执胶囊与录音控制坞。

### Axis Z · Apple 双层材质（`Functional Glass` vs. `Solid Content`）
- **Top Z-Layer（Functional Chrome — iOS 26 Native Liquid Glass）**：
  - 底部悬浮录音坞与状态回执胶囊包裹在 `GlassEffectContainer(spacing: 12)` 中，使用原生 `.glassEffect(.regular.interactive(), in: .capsule)` 与 `.glassEffectID` 流体形变；主录音按钮采用 `.buttonStyle(.glassProminent)` + 语义强调色 `.tint`（开启「降低透明度」时自动回退 `.thickMaterial`）。
  - 桌面 Widget（`QuickRecordWidget`）、控制中心控件（`VoxPocketControlWidget`）与灵动岛（`VoxCaptureLiveActivity`）全部使用 `Button(intent:)` 触发 `AudioRecordingIntent`（`openAppWhenRun = false`），无需打开主 App 即可后台一键开启/停止录音。
- **Bottom Z-Layer（Solid Content Canvas）**：Todo 列表背景使用 `L0` `systemGroupedBackground`，Todo 卡片使用 `L1` `secondarySystemGroupedBackground`（无厚重 1px 描边，以底代框）。

---

## 3. 呼吸感五抓手与零猜测 UX 细则（`breathing-and-clarity.md`）

### 3.1 呼吸感五抓手量化参数（落地于 `AppTheme.swift`）
1. **内紧外松间距比（`1 : 3 : 6`）**：
   - 元素内间距（标题↔副标题、图标↔文字）：`Space.xs = 4pt` / `Space.sm = 8pt`
   - Todo 卡片内边距：`Space.lg = 16pt`（严格大于内部行间距 `8pt`）
   - 区块外间距：`Space.xxl = 24pt`
2. **以底代框（Borderless Luminance Tiers）**：
   - Todo 卡片采用 `RoundedRectangle(cornerRadius: 16, style: .continuous)` + `AppTheme.surfaceCard` 填充，移除冗余外框线，卡片间距 `10pt`。
3. **字重拉开与次要退后（Typographic Scale & Contrast Retreat）**：
   - 全屏仅 4 级字号：导航大标题、`16pt (.body.weight(.semibold))` 待办标题、`13pt (.footnote)` 任务摘要（`.secondary`，最多 2 行）、`11pt (.caption2.monospacedDigit())` 时间与项目标签（`.tertiary`）。
4. **90/10 色彩克制**：
   - 90% 中性画布，仅在主录音按钮、当前激活筛选胶囊与状态图标使用语义强调色。

### 3.2 零猜测法则（`说法 · 入口 · 反馈`）
1. **说法（大白话意图表达）**：
   - 设置项拒绝使用“CaptureMode / 输出路由 / 剪贴板管道”等开发术语，直接命名为 **「录音完成后去向」**：
     - 选项 A：**「直接存入待办」** — *“自动提炼标题并加入首页待办清单”*
     - 选项 B：**「自动复制到剪贴板」** — *“润色为干净文字并复制，方便直接粘贴”*
   - 提供清晰的 **「iPhone 操作按钮（Action Button）快速录音」** 引导卡片：用大白话说明如何在「系统设置 → 操作按钮 → 快捷指令」中选择「VoxPocket · 开始录音」。
2. **入口（就地可切 + 高级收起）**：
   - 底部悬浮录音坞平时直接展示当前录音去向胶囊（`存入待办` / `复制文字`），点按即可就地切换；录音过程中也可随时轻点切换本次录音去向。
   - 右上角工具栏提供「设置」入口，集中管理默认录音去向与模型/隐私高级项。
3. **反馈（确定性结果回执）**：
   - 录音结束并处理完成后，底部录音坞上方弹出无遮挡回执胶囊，配以 `SensoryFeedback.success`：
     - 若去向为 Todo：显示绿色对勾 + **「已存入待办 · <标题>」**，列表同步插入新 Todo 且顶部待处理计数 `.contentTransition(.numericText())` +1；
     - 若去向为剪贴板：自动写入 `UIPasteboard.general.string`，显示绿色对勾 + **「已复制到剪贴板 · 可直接粘贴」**。

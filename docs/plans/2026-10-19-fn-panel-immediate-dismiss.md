# Fn 松手立即隐藏快捷录音面板

Last-Reviewed: 2026-10-19

## 受审定义

Revision: r1。PR kind: bugfix。定义方及协调者为主会话；唯一 Target 写者为
`quick_record_writer`；独立 reviewer 另派，未参与实现。执行依据是 Owner 本次明确请求：
「松开 fn 后 panel 立刻消失，转写、润色、粘贴在后台照常完成；出错时也不能让
panel 一直留在屏幕上」，补 Fn 松开和 panel 关闭两个 telemetry 事件，最后提交 PR。
独立计划审查 APPROVED 后，按这项已明确的实施授权执行，不重复索取相同授权。

## Goal G1

Fn 的 release 回调到达 AppDelegate 后，在同一 MainActor 执行片段内隐藏当前快捷
录音面板，不等待录音停止、识别、润色、粘贴、存储或固定延时。面板隐藏与后台任务
生命周期解耦，既有最终文本、自动粘贴和会话保存继续完成。正常、无结果、启动／停止
失败以及保存失败都不能留下可见面板。用两个无正文 telemetry 事件度量 release 到
面板实际隐藏的延迟。

代码层为 VoxPocketApp，以及 VoxInfrastructure 的遥测名称类型；测试脚本和本计划
属于 support。保留既有录音互斥、已有 Blob 产品事件及隐私边界。不改转写／润色算法、
粘贴策略、热键注册、UI 视觉、SDK、依赖、配置、CI／门禁、发布或用户数据格式。
当前交付边界为一个可审 PR 和该 head 的必要检查证据；合并由仓库授权 PR Manager
或 Owner 执行，真实设备体验和 TestFlight 验收不得从自动化结果推断。

## Target T1：快捷录音立即消失且后台收尾可靠

父级 G1；依赖为现有仓库和 CI。基线为 `origin/main`
`c276ff1a52395ee959145294df19c716b2c1d1a6`，独立 branch/worktree。
一个写者、一个 PR，Tasks 内不另建 PR。初始 `scripts/verify` 已由写者通过。

### 已确认现状与设计约束

- AppDelegate 的 onComplete 在保存后固定 sleep 1 秒再 hide/end；停止错误只 end。
- WindowManager 的 hideWindow 对快捷录音执行 closeWindow，释放保存的 ViewModel；
  willClose 回调还会取消处于 listening 的模型。直接把现有 hide 移到 stop 前会误取消。
- 因此增加仅负责视觉隐藏的窗口入口：同步 orderOut 和更新可见性，保留该会话模型；
  不触发 close 的取消路径。后台终态仍通过既有 close 语义释放窗口和模型。
- 松手先捕获当前模型并隐藏，再 await stop。启动未完成时，继续沿用模型已有的待停止
  请求；启动恢复后完成一次 stop。隐藏后保留录音占用到后台终态，拒绝重叠录音。
- 成功、无结果和错误走幂等终态清理；启动期间松手后若启动失败，同样释放占用。
  移除固定 1 秒 sleep。完成保存的异步工作必须持有必要的原始／最终文本快照，避免
  隐藏／释放模型导致数据丢失；保存失败仍完成清理，旧回调不得关闭后来的会话。

### Owned paths

生产：

- `VoxPocket/VoxPocket/AppDelegate.swift`
- `VoxPocket/VoxPocket/AppDelegate+QuickRecording.swift`（如需拆分所触及的大函数）
- `VoxPocket/VoxPocket/WindowManager.swift`
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/VoxPocketTelemetryEventName.swift`

测试和配套计划：

- `VoxPocket/VoxPocketTests/QuickRecordingWindowLifecycleTests.swift`
- `VoxPocket/VoxPocketTests/QuickRecordingImmediateDismissTests.swift`
- `VoxPocket/VoxPocketTests/QuickRecordingImmediateDismissTestSupport.swift`
- `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift`
- `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTestSupport.swift`
- `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/VoxPocketTelemetryEventNameTests.swift`
- `scripts/tests/test_quick_record_release.py`
- `scripts/tests/quick_record_release_probe.swift`
- 本文件（定义仅由定义方修订；写者仅提交已受审版本）。

需要新增文件、改变设计或发现基线失败，提供证据回协调者；不得自行扩范围。
不修改 project.yml，新增 app/test Swift 文件沿用其既有目录自动发现。

### Task A：事件契约及延迟

父级 T1／VoxInfrastructure → VoxPocketApp；依赖无。新增名称
`quick_record.fn_released`、`quick_record.panel_closed`，通过既有非阻塞
`TelemetryService` facade 发送，不扩 Blob 事件白名单。仅当前成功 claim 的快捷录音
会话发出该事件对；Fn 松手事件在处理有效 release 时发出，panel_closed 在视觉隐藏
操作返回后发出，均在第一个 await 前。以同一随机 `session_id` 关联一次录音，
`source` 为固定来源标签，关闭事件的 `duration_ms` 用 ContinuousClock 从 release
入口算起。panel_closed 在这里明确定义为用户可见面板已隐藏，而非后台模型销毁。
重复 release、无模型、被其他录音占用的事件语义须在测试中确定，不重复发关闭事件。
只允许计时、标签和会话 ID；不得发送音频、文本、错误正文或身份信息。
验收映射 C1、C5；命令见下表。

### Task B：App 接线及可靠生命周期

父级 T1／VoxPocketApp；依赖 A。实现上述同步视觉隐藏、后台保活、启动竞态与幂等
终态清理，完成及无结果回调不再依赖面板可见。停止错误、启动错误、空模型和保存失败
同样清理。保留现有 Blob quick-record start/stop 行为。触及函数／初始化器保持
小于 50 行，文件小于 800 行；必要的局部拆分留在上述路径内。
验收映射 C1–C4；命令见下表。

### Task C：回归、提交和 PR

父级 T1／相应 app、Infrastructure 测试及 support；依赖 A/B。先添加有界、无实际录音
的可控挂起回归：启动、停止／识别、润色／粘贴、保存未完成时，面板已隐藏且互斥仍在；
放开挂起后确认后台产出、一次粘贴／保存及终态释放。覆盖快速松手、无结果、启动／
停止错误、保存错误、重复 release 和连续下一次录音。真实 WindowManager 测试证明
仅隐藏不取消模型，最终 close 释放模型。保留已存在断言，更新确实改变的预期并在 PR
说明原因；不得通过删除或弱化断言绕过失败。既有生产源码注入 probe 继续绑定生产
handlers，可随 scoped helper 提取适配 harness。正常 hooks 提交、push、按模板建 PR；
记录准确 SHA 和命令结果，等待该 head 的 required checks，失败由原写者修复。

## 验收映射

| ID | Goal → Target → Tasks 的验收 | 验证命令与证据 |
|---|---|---|
| C1 | G1 → T1 → A/B/C：有效 release 在 await 前隐藏，后台挂起也已消失 | `python3 scripts/tests/test_quick_record_release.py`；CI macOS App tests |
| C2 | G1 → T1 → B/C：隐藏不取消；识别、润色、粘贴、保存完成且各一次，保存前保持互斥 | 同上，App gate 生产 handlers probe + CI App tests 的受控边界 |
| C3 | G1 → T1 → B/C：快速松手、无结果、启动／停止／保存错误均隐藏、释放，下一次录音可用 | 同上，错误及重试测试输出 |
| C4 | G1 → T1 → B/C：真实窗口隐藏保留模型，终态关闭释放；无延时、无旧回调串会话 | CI macOS `QuickRecordingWindowLifecycleTests` 和 `QuickRecordingImmediateDismissTests`；内容审查 |
| C5 | G1 → T1 → A/C：事件对顺序、去重、同 session_id、非负耗时和隐私属性 | 生产 handlers probe；`swift test --package-path Packages/VoxInfrastructure --explicit-target-dependency-import-check error --filter VoxPocketTelemetryEventNameTests`；CI App tests |
| C6 | G1 → T1 → C：不越界、层方向及隐私合规，准确 head 的仓库必要检查通过 | 写者 `scripts/verify`、`scripts/verify --policy`，正常 hooks；PR required checks；独立 V1–V3 验收 |

SwiftPM 构建／测试按 xcode-cli skill 执行。使用现有 Python 3.11+；本地不运行
xcodebuild、不创建或启动交付 build。App/macOS 与 iOS 编译及 app XCTest 依仓库
CI 实际 lane 取证，未执行的测试不得写为通过。若 CI 没有运行所列 App 测试，必须
回报为证据缺口，由定义方处理，不能把 source probe 冒充真实 App 运行。

## 独立审查与执行台账

计划先独立审查至 APPROVED；执行后独立 reviewer 只读准确定义、diff 和命令证据，
按 V1–V3 判断范围、验收覆盖和红线，不代跑 build/test/lint 或裁定 CI。上一轮 findings
及修复 delta 带入复审，同一问题两轮不过回定义方。独立验收不能由写者自检替代。
writer/reviewer 会话 ID、计划 verdict、PR/head、验证输出及下一动作存于 PR 描述／
评论或未跟踪的会话台账；这些进度不修改冻结定义。执行请求的授权来自上述 Owner
明确请求，plan APPROVED 是实施前置。交付报告区分 PR、CI、合并及实机验收状态。

回滚为 revert 本 PR，无数据／配置迁移。主要风险为 close 误取消、后台模型提前释放、
重复清理及旧回调干扰新会话，均由上述挂起／错误／重复触发回归覆盖。

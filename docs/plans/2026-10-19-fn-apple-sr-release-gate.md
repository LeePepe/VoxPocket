# Fn 松手按 Apple SR 决定继续或取消

Last-Reviewed: 2026-10-19

## 受审定义及授权

Revision: r2.1（r1 的有界增量；仅补隐私测试 fixture owned path）。PR kind: bugfix。
定义方及协调者为主会话 `/root`；当前 Task 唯一写者沿用 `quick_record_writer`，
独立验收沿用 `quick_record_acceptance`，不参与实现。
遵循当前 goal-target-task 合同及仓库规则，协调者不实现或独立验收产品代码。

既有 r1 为 [立即隐藏计划](2026-10-19-fn-panel-immediate-dismiss.md)，SHA256
`adf308af84e7f6c629743379cf4a30d694a3acfd99b3a6145bee81e1624a25e2`，
已验收实现 head 为 `5ff584aafc0a189acea2b9d4452e27ee3a0a2bfb`，PR #125。
该定义及既有有效结论保留；本文件仅修订继续后台处理的条件，增加所需取消路径和验收。
先独立审查本增量至 APPROVED，再执行。授权来自 Owner 追加要求使用 Apple SR
判断是否识别到文字，以及明确回答「直接结束，不再转写、润色或粘贴」。
这已是明确的实施授权，不重复请求同一授权。

## Goal G1（追加约束）

保留 r1 的 Fn release 同步隐藏面板、后台保活、幂等终态清理及两个无正文 telemetry
事件。松开时，仅本次录音的 Apple SR 已识别过非空白文字，才继续最终转写、润色、
复制、粘贴和保存；否则直接取消，不执行这些收尾操作。

本增量涉及 VoxInfrastructure、VoxApplication、VoxPresentation、VoxPocketApp
及配套测试／计划。仅决定 release 后的继续与取消；不改变 Fn 按住期间已发生的实时
识别、云预览或流式润色。无首次 Apple 结果宽限期，不以音频长度、电平、VAD、
云文本、最终结果或排队中的 UI 显示文字代替 Apple 来源证据。
不改编辑器普通 stop 语义、模型／润色算法、热键、视觉、遥测 schema、配置、依赖、
门禁或发布。交付边界仍为 PR 及准确 head 的检查／验收证据；不自行合并或发布。

## Target T1-r2：立即隐藏并可靠选择后台完成或无结果取消

父级 G1；依赖 r1 的已验收内容和现有 CI。复用 PR #125 的独立 branch/worktree，
从上述准确 head 作增量；同一 release 生命周期目的、同一写者、同一独立验收方式，
不引入第二写者或临时 stacked PR。若 #125 在写入前已合并，暂停分支变更并回报协调者
路由，保留现场，不重复提交 r1。旧 head 的绿灯不作为新 head 的证据。

### Task W1：Apple 来源快照与不转写取消

父级 T1-r2；固定唯一写者 `quick_record_writer`。原 r1 A/B/C 是该写者已完成的
历史步骤，本次不重写其定义。W1 包含本增量的实现、必要回归、正常 hooks、提交、
push、更新 PR 及新 head CI 跟进。协调者定义和路由，原写者实现及修复，独立 agent
确认内容与证据覆盖；不自行扩大定义。

必须满足的接口和行为：

1. 源端提供窄的 quick-release capability：同步冻结当前录音的 Apple 识别资格及
   session token，随后对同一 token 执行可等待的完成或丢弃。状态在启动首次挂起前
   重置，旧会话回调不计入；本会话在 starting 或 recording 收到的 Apple partial／
   final 非空白文本均可资格成立，之后空白回调不撤销。只保留必要状态，不额外保存
   内容。共享跨任务状态用 Mutex<State>，UI 用 MainActor。
2. quick ViewModel 在 release 同步前缀、首次 yield／await 及 startup 早退之前只
   冻结一次；启动／streaming 初始化未结束时保留决定，后续 Apple 文本不能把取消
   升级为继续。snapshot 与执行针对同一 session；重复 release／旧 token 不影响新会话。
   原 AppDelegate 同步 hide 和两个事件仍先于异步收尾，不新增可见等待。
3. 有资格时保留 r1 的最终结果订阅先于 finalization、后台润色／复制／一次粘贴／
   一次保存及错误清理。无资格时先使 streaming／refinement 的后续提交失效，再等待
   录音取消、Apple task／realtime 取消和临时音频清理；跳过整个 finalizer，不能以
   normal stop 充当 discard。无 realtime finish／commit、batch／fallback／merger、
   新 final publication、release 后新 refinement、复制／粘贴／保存／onComplete。
   cleanup 完成后走 no-result 终态，释放模型和录音占用；失败也收敛清理并保持隐藏。
4. selectable coordinator 转发同一 session 的快照／动作，封住被丢弃会话的迟到输出。
   覆盖实际 macOS quick 栈的 Apple-only、batch hybrid、realtime hybrid。
   非 quick 的普通 stop，包括无 Apple partial 但音频足够而正常完成，保持原行为。
   不扩展 standalone Azure／local Whisper 等未组装的替代 provider；不支持的 quick
   capability 必须显式失败且不开始正常 finalization，不能悄悄退回云／音频判断。
5. 必须用可注入的确定性 callback／effect seam 验证真实 orchestration 的取消路径，
   无麦克风、权限对话框、网络或真实内容。仅复制一个 Boolean predicate 的测试不够。
   新接口和小函数的具体名字由写者在这些约束内选择。

### Owned paths

生产（仅为上述行为所需的最小改动）：

- `Packages/VoxInfrastructure/Sources/TranscriptionKit/QuickRecordingReleaseControlling.swift`（新）
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/HybridRecordingLifecycle.swift`
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/HybridWhisperTranscriber.swift`
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/AppleSpeechTranscriber.swift`
- `Packages/VoxInfrastructure/Sources/TranscriptionKit/DefaultSelectableTranscriptionCoordinator.swift`
- `Packages/VoxApplication/Sources/UseCases/RecordingUseCase.swift`
- `Packages/VoxApplication/Sources/UseCases/DefaultRecordingUseCase.swift`
- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift`
- `VoxPocket/VoxPocket/ServiceContainer.swift`（仅若需窄 capability 注入）
- `VoxPocket/VoxPocket/AppDelegate.swift`（仅若需同步快照接线，不移动 hide／telemetry 到 await 后）

测试、必要的 scoped helper 和计划：

- `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/HybridRecordingLifecycleTests.swift`
- `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/SelectableTranscriptionTests.swift`
- `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/QuickRecordingReleaseControlTests.swift`（新）
- `Packages/VoxInfrastructure/Tests/TranscriptionKitTests/QuickRecordingReleaseTestSupport.swift`（新，必要时拆分）
- `Packages/VoxApplication/Tests/UseCasesTests/QuickRecordingReleaseUseCaseTests.swift`（新）
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingViewModelTests.swift`
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingLoggerPrivacyTests.swift`
  （仅适配 recording fake 的 quick-release capability／本 session Apple 资格；保留原有
  completion 和原始／润色文本不入日志的全部断言，不改变生产日志／telemetry 行为）
- `VoxPocket/VoxPocketTests/QuickRecordingImmediateDismissTests.swift`
- `VoxPocket/VoxPocketTests/QuickRecordingImmediateDismissTestSupport.swift`
- `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTestSupport.swift`
- `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift`（仅若需 capability fixture／取消行为断言）
- `scripts/tests/test_quick_record_release.py`、`scripts/tests/quick_record_release_probe.swift`
  （仅若 handler 接口变化需适配真实生产源码 probe，保留所有原时序和隐私断言）
- 本文件（定义由协调者编制；写者仅提交已受审版本）。

未列路径、超过文件／函数限制而需拆分、或实际基线阻塞，先带证据回协调者；不默许
新增 scope。不改 r1 文档、WindowManager、事件 catalog、project.yml 或其他契约文件。
写者不是代码库中唯一活动者，不回滚他人改动；发现未知写入先对账。

## 增量验收映射

| ID | G1 → T1-r2 → W1 的验收 | 命令及必要证据 |
|---|---|---|
| D1 | 非空白 Apple 源证据；cloud／audio／UI 不可替代；空白不资格，早先有效识别可资格 | Infrastructure focused tests；Application focused tests；Presentation focused tests；只读内容审查 |
| D2 | 无资格实际取消路径零 finalization／publication／release 后新 refinement／copy／paste／save；资源恰好一次收尾 | Infrastructure 的真实 orchestration 注入 counters；Application awaited discard；Presentation 和 CI App 集成 counters |
| D3 | starting／授权或选择挂起／streaming 初始化挂起、早期和迟到 Apple、旧会话／token、重复 release、失败和下一次录音；不在取消后启动新 capture | 三层 focused tests 与 CI App 集成测试的确定性 suspension/callback 证据 |
| D4 | 两分支同样立即隐藏且 cleanup 前保持占用；有资格的 r1 完整产出／错误语义；原事件对顺序、会话 ID、隐私及 Blob 顺序 | 生产 handler probe；CI macOS QuickRecordingImmediateDismissTests、QuickRecordingWindowLifecycleTests、BlobTelemetryInstrumentationTests |
| D5 | Apple-only／batch／realtime 选路均执行 gate；普通 editor stop 保持既有音频／final 行为；无跨层或隐私违规 | Infrastructure/Application tests；保留原 ordinary-stop 回归；只读 diff／接口审查 |
| D6 | 准确新 head 的正常 hooks、verify／policy 及九项 required checks；实际 macOS App 测试执行，证据覆盖 r1+r2 组合结果 | 写者日志与 CI job／test receipts；独立 agent 按 V1–V3 确认证据映射，不代跑或重裁 gates |

Focused commands（SwiftPM 按 xcode-cli；Python 3.11+）：

```sh
swift test --package-path Packages/VoxInfrastructure --explicit-target-dependency-import-check error --filter 'HybridRecordingLifecycleTests|SelectableTranscriptionTests|QuickRecordingReleaseControlTests'
swift test --package-path Packages/VoxApplication --explicit-target-dependency-import-check error --filter QuickRecordingReleaseUseCaseTests
swift test --package-path Packages/VoxPresentation --explicit-target-dependency-import-check error --filter 'QuickRecordingViewModelTests|QuickRecordingFinalResultWaiterTests|QuickRecordingLoggerPrivacyTests'
python3 scripts/tests/test_quick_record_release.py
scripts/verify
scripts/verify --policy
```

本地无 xcodebuild、交付 build 或真实录音；App/macOS/iOS 编译测试由 CI 取准确 head
的执行证据。未执行的 App 测试不能用源码 probe 冒充。原 r1 C1–C6 的内容批准保留，
但 C2 的后台继续限定为本增量有资格分支，空分支改按 D2；新 head 重新取所需运行证据。

确实需要改变的旧测试预期：quick release 的 final-without-Apple 现在应取消；原 eligible
粘贴／保存测试 fixture 应显式提供本 session Apple 资格并保留产出断言。PR 必须说明
原因，不删减普通 stop 的无 partial 最终结果断言，也不弱化时序／错误／隐私断言。

## 冻结、独立审查及交付

候选交独立 reviewer 审查字段、增量、映射及红线，CRITICAL／MEDIUM 修复后复审至
APPROVED；实施交接记录准确 hash。按 V1–V3 只审 r2 及后续 repair delta，不重开
r1 未变化的内容。reviewer 直接读定义、diff 和命令证据；两轮同题不过交回定义方。
运行证据、agent/session、PR/head、finding 和下一动作记外部执行台账／PR，不改冻结定义。
写者正常 hooks commit/push，按模板重写 PR 最终目的、预期变化理由和新 SHA 证据，
跟进 required checks，CI 问题按引入来源回原写者；不更改 gates 或自行合并。
回滚为 revert r2 增量，无数据或配置迁移。未合并、未实机验收和未发布状态须如实报告。

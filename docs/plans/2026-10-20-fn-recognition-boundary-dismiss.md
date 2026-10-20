# Fn 有识别结果时在转写完成后隐藏面板

Last-Reviewed: 2026-10-20

## 定义与基线

Revision: r3.1（补识别早期终稿捕获及对应 owned paths；r3 尚未交实现）。PR kind: bugfix。定义方／协调者 `/root`；Task W2 唯一写者沿用
`quick_record_writer`；独立验收沿用 `quick_record_acceptance`，不参与实现。
执行合同为当前 goal-target-task；交接和外部台账记录其路径、SHA256、审查基准和
执行实际加载版本。协调者只定义、分配和报告，不实现或自签验收。

授权来自 Owner 的追加修正：「如果 Apple识别到了，应该等识别完成再消失panel」。
此前已定的空分支「直接结束，不再转写、润色或粘贴」继续有效。本次是明确的修正
实施请求；独立计划审查 APPROVED 后按该授权执行，不重复索取同一授权。

保留已合并 PR #125 的受审历史定义及结论，不改以下冻结文件：
- `2026-10-19-fn-panel-immediate-dismiss.md`，SHA256 `adf308af84e7f6c629743379cf4a30d694a3acfd99b3a6145bee81e1624a25e2`。
- `2026-10-19-fn-apple-sr-release-gate.md` r2.1，SHA256 `e730a2aed4e220d51ed352c542b1f9ffc070b08579e086b0a62fc4e692f90b2b`。
- 累计已验收 head `66cd0c5bcf7d3e51409c8ea027add9ee989f51d0`，merge `8e69ce18bf8e1398fb4bdbc6c9491a17b0eb775c`。

新执行基线为 `origin/main` `cecf39d1c8e4ebcaed825b436264fec0caef1f11`；新 branch、
worktree、PR，不修改已合并 #125，不重交旧变更。当前共享协议 pin 为
`88c09b3f68ceea82a4ca979c689e3dc50266ee10`。新 head 必须有新证据。

## Goal G1-r3（Owner 修正）

松开 Fn 时按同一 session 已冻结的 Apple SR 来源资格分流：没有非空白 Apple
识别证据时立即隐藏并真正 discard；已有证据时保留面板，直到当前已配置识别链的
最终转写被现有 final-result／fallback 机制确定，立即隐藏，再在后台完成流式润色
收尾、普通润色、复制、一次粘贴和一次保存。识别失败或超时不能无限保留面板。

这里 Apple SR 继续只负责 release 资格；“识别完成”使用现有最终转写边界，包含
当前 provider 的 batch／realtime／merger，不能等到 refinement／paste／save，也不
把它解释为仅 Apple `isFinal`。此边界按 Owner 原句与现有配置作默认解释；若 Owner
明确选择只等 Apple 自身终稿，先回定义方修订并重新审查，不能悄悄改变接口。

层为 VoxPresentation、VoxPocketApp 及配套测试／计划。保留 r2.1 的来源、sticky
snapshot、session token、无迟到升级、真正 discard、F1 post-await identity guard、
普通 editor stop、隐私和互斥。不改识别／润色算法、provider 选择、热键、视觉、
遥测 schema、SDK、依赖、配置、CI／门禁。SDK 状态问题仅只读核查，不纳入实施。
本次不包含额外手动 TestFlight；已完成的 macOS 1.0 build 48 发布保留。

## Target T2：面板按识别阶段关闭，后台生命周期保留

父级 G1-r3；依赖已合并 T1／r2.1、现有 final publisher 和准确 head 的仓库 CI。
本 Target 只修订 eligible 分支的隐藏时间及因此必需的失败、超时、事件、测试。

### Task W2：识别边界接线、回归及一个新 PR

父级 T2；固定唯一写者 `quick_record_writer`。实现、验证、正常 hooks、commit、
push、按模板建 PR、处理准确 head 的检查及原路径修复均归原写者。
独立 reviewer 按 V1–V3 确认本 delta、累计保留约束及证据映射；不代跑 gates。

行为／接口约束：

1. release handler 在第一个 await／Task 调度前同步冻结一次 Apple 资格。可提取
   ViewModel 的窄同步 preparation 接口，由现有 stop 复用，不能重新冻结或改变
   snapshot。空分支、无模型和同步准备错误立即隐藏；eligible 分支暂不隐藏。
2. ViewModel 提供不含文本的识别阶段结束通知。同 session 的 final-result capture
   在 quick prepare 后、startup 第一次挂起前注册，保留早于 release 到达的终稿；
   deadline 只在 release 时启动，不能在按住 Fn 期间耗尽等待预算。丢弃、启动失败、
   终态及下一次录音取消旧 capture；旧 session 的结果不能污染新 capture。在最终 raw text 已按现有 policy 确定之后，且显式等待下游
   `stopStreaming`、commit/refinement、copy/paste 或保存之前发出通知。
   App 同步视觉 hide 后立即记 panel_closed；保留 VM／任务直到既有后台终态。
   既有 streaming refinement 可随 final publisher 自动并发开始，不为此新增队列／
   串行屏障；面板隐藏不等待这些工作，按住 Fn 期间的实时润色行为不变。
3. 现有向 VM/App 传播的识别／启动错误、取消、无结果都幂等隐藏；源端未传播的
   Apple 错误及识别前的可挂起调用由以下 deadline 兜底，不增加底层错误协议。
   从有效 release 起复用现有 final waiter 的 15 秒预算设置独立、可取消的 UI
   watchdog。正常识别通知先到则立即 hide 并取消 watchdog；错误先到也立即 hide；
   真正挂起时预算到期只兜底隐藏，不伪造识别完成或释放仍在收尾的 session，原
   pipeline／资源互斥仍保留至实际终态。不能使用等待非协作子任务结束的 task-group
   timeout；不能新增识别完成后的固定 sleep。测试通过注入短预算／可控时钟确定性
   验证 watchdog，不等待真实 15 秒。
4. Fn 松开事件仍在有效 release 入口发一次；panel_closed 在实际视觉 hide 后发
   一次，成功、空、失败、watchdog 路径共享去重与 session 检查。两事件同
   session_id，duration_ms 从 release 的 ContinuousClock 起点量至实际 hide；
   不增加文本、音频、错误正文或身份属性。旧通知／watchdog 不得关闭新 session。
5. 隐藏和最终 close 继续分离。隐藏不能取消 background refinement、paste/save；
   pending pipeline／cleanup 时占用不提前释放。终态继续一次释放；重复 release、
   快速 release、starting／streaming 启动挂起、重试和保存错误均不能串会话。

### Owned paths（仅为上述目的的最小改动）

生产：
- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingViewModel.swift`
- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingFinalResultWaiter.swift`（分离 session capture 和 release 才启动的 deadline，保留原有默认预算及 fallback 行为）
- `Packages/VoxPresentation/Sources/PlatformUI/QuickRecordingReleaseLifecycle.swift`（必要时新建，局部同步 preparation／通知／timeout helper）
- `VoxPocket/VoxPocket/AppDelegate.swift`
- `VoxPocket/VoxPocket/AppDelegate+QuickRecording.swift`（必要时新建，仅拆所触及接线；同 session 私有实现按 Swift 可见性最小调整）

测试／配套：
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingViewModelTests.swift`
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingFinalResultWaiterTests.swift`（提前 final、延后 arm、取消与重复完成回归）
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingRecognitionBoundaryTests.swift`（必要时新建）
- `Packages/VoxPresentation/Tests/PlatformUITests/QuickRecordingLoggerPrivacyTests.swift`（仅必要 fixture／边界适配，保留隐私及完整产出断言）
- `VoxPocket/VoxPocketTests/QuickRecordingImmediateDismissTests.swift`
- `VoxPocket/VoxPocketTests/QuickRecordingImmediateDismissTestSupport.swift`
- `VoxPocket/VoxPocketTests/QuickRecordingRecognitionBoundaryTests.swift`（必要时新建）
- `VoxPocket/VoxPocketTests/QuickRecordingRecognitionBoundaryTestSupport.swift`（必要时新建）
- `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTests.swift`
- `VoxPocket/VoxPocketTests/BlobTelemetryInstrumentationTestSupport.swift`
- `scripts/tests/test_quick_record_release.py`
- `scripts/tests/quick_record_release_probe.swift`
- 本文件，写者只提交独立批准的准确版本，不能改冻结定义。

不修改 Infrastructure／Application、WindowManager、事件 catalog、final waiter policy、
project.yml、SDK、旧计划或其他契约文件。若实际需增加文件／接口、拆分文件、测试
helper 或遇到基线阻塞，先附准确证据回协调者修订，不自行扩大。写者不是唯一活动者，
不撤销他人工作，未知写入先对账。新 helper 遵守 <50 行函数、<800 行文件和层方向。

## 验收映射（G1-r3 → T2 → W2）

| ID | 可观察验收 | 命令和必要证据 |
|---|---|---|
| E1 | early final 在 prepare 后／release 前可保留且不额外等待；eligible 在 stop／recognition 受控挂起时 panel 可见，最终转写边界立即 hide；refinement／streaming stop／paste／save 受控挂起时已隐藏且最终各一次产出 | Presentation focused tests；生产 handler probe；CI macOS App integration tests |
| E2 | 空分支同步 hide；真实 discard、无 late upgrade、无 release 后新转写／润色／copy／paste／save；原 F1 和 ordinary-stop 约束保留 | 保留原 Infrastructure／Application 回归的新 head 证据；Presentation tests；probe／App tests |
| E3 | 启动／停止识别失败、无结果、取消、永不返回的 stop/start 路径有界 hide；15 秒 watchdog 可取消且不会等待挂起 provider，隐藏不伪造终态／取消正常后台输出 | 可注入短预算及受控 continuation；probe；CI App tests；内容审查 |
| E4 | 两事件实际时序、准确耗时、同 session_id、去重、隐私；eligible 的等待计入 duration_ms | 生产 probe；CI QuickRecordingRecognitionBoundaryTests 与 BlobTelemetryInstrumentationTests；原隐私测试 |
| E5 | startup／streaming 初始化、重复 release、旧 session callback/watchdog、下一次录音与终态互斥；实际 WindowManager hide 保活／close 释放保持 | Presentation tests；probe；CI QuickRecordingImmediateDismissTests、QuickRecordingRecognitionBoundaryTests、QuickRecordingWindowLifecycleTests |
| E6 | 准确 head 的正常 hooks、verify、policy 与九项 required checks；实际 macOS App tests 执行；必要 iOS build/test 无回归 | 原写者日志、CI checks 和实际测试计数／结果；独立验收读取证据，不代跑或重裁 |

```sh
swift test --package-path Packages/VoxPresentation --explicit-target-dependency-import-check error --filter 'QuickRecordingViewModelTests|QuickRecordingRecognitionBoundaryTests|QuickRecordingFinalResultWaiterTests|QuickRecordingLoggerPrivacyTests'
swift test --package-path Packages/VoxInfrastructure --explicit-target-dependency-import-check error --filter 'HybridRecordingLifecycleTests|SelectableTranscriptionTests|QuickRecordingReleaseControlTests'
swift test --package-path Packages/VoxApplication --explicit-target-dependency-import-check error --filter QuickRecordingReleaseUseCaseTests
python3 scripts/tests/test_quick_record_release.py
scripts/verify
scripts/verify --policy
```

SwiftPM 按 xcode-cli skill；Python 3.11+。不本地 xcodebuild、不录真音、不创建或
启动交付 build。App/macOS/iOS 依 CI 实际 lane 取证；source probe 不冒充 App tests。
旧 eligible “立即隐藏”预期按 Owner 修正替换为“识别前可见、识别后即隐藏”，保留
空分支、后台产出、错误／session／隐私全部义务，并在 PR 说明预期变化理由。

## 独立审查与交付

先对本 r3 delta 独立计划审查至 APPROVED，再交原写者执行；不重开旧 r1／r2.1
未变化内容。finding／repair 按两轮上限处理。内容批准、执行证据待齐、自动化验收
通过、PR 交接、合法合并、发布／实机验收分开记录。运行收据记外部执行台账或已授权
PR 评论，不为补收据反复编辑 PR body 触发 CI。只有准确 head required checks／AI
review 通过后，由仓库授权的 PR Manager／Owner 合法合并；原写者跟进 merged readback，
不直接使用错误身份合并。回滚为本 PR 的 forward revert，无数据／配置迁移。

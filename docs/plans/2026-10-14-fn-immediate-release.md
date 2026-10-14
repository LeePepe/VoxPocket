# Fn 立即松手收尾修复计划

Last-Reviewed: 2026-10-14

## 目标与范围

修复 Fn 按下后立即松手的快捷录音收尾：结束录音一次，空结果结束流式会话并通知宿主关闭浮窗，后续录音可以正常启动。保留有内容时的最终转写、润色与自动粘贴。需求来源为本次 Owner 的修复并提交请求，以及 [FR-005](../../specs/001-fn-transcript-island/spec.md)。PR kind：bugfix。

修改 VoxInfrastructure 的实时音频收尾资格检查及 VoxPresentation 的快捷录音生命周期和对应测试；不改变 UI、模型选择、依赖、App 接线或交付策略。

## 代码诊断与证据边界

- `HybridRecordingLifecycle.Session.shouldFinalize` 只要存在 realtime pipeline 就返回 true，即使 Fn 松手时尚未收到音频 buffer。底层 stop 因而等待远端连接/收尾；`DefaultRealtimeTranscriptionSession.finish()` 对不足 4800 字节的 24kHz PCM（100ms）报 emptyTranscript，随后 `RealtimeASRFinalizer` 继续执行整文件回退。无可提交音频也走完整网络收尾是快速松手 loading 的直接可测试路径。
- 修复资格判断以已采集的有效音频时长为准（至少 100ms，与现有服务提交下限一致），或已有真实识别文字；不将「尚无 partial」视为静默。有效音频尚无 partial 时仍保留实时排空和一次 batch fallback。

- `QuickRecordingViewModel.startRecording()` 在 `startStreaming()` 完成之前清除启动标志；松手任务可在流式启动尚未结束时执行停止。
- `stopRecording()` 的无语音分支未调用流式协调器 `cancel()`，留下快照门控、订阅及语音编辑区锁；应按无结果终态清理。
- `makeFinalResultWaitTask()` 由新 Task 再订阅 Passthrough publisher；同步停止返回的 final 可能在订阅之前发出而丢失。空 final 被忽略，任务继续等待；取消和超时也应明确释放订阅。
- 现有快速松手测试仅验证底层 stop 调用一次，已通过；不覆盖真实实时 pipeline、空结果后的资源状态及同步 final。上述结论来自代码和合成测试，不宣称取得真实设备运行日志或重现无限等待。

## 实施步骤

1. 添加有界回归测试：零 buffer 及不足 100ms 音频不进入网络收尾，有效音频无 partial 仍完成实时/回退；使用可控的启动挂起、流式启动挂起、同步 final 和不会完成的 publisher，证明快速松手不会遗留流式会话；验证关闭回调一次、停止一次、不粘贴空结果以及连续下一次录音可启动。使用 XCTest expectation 限制失败等待，不让测试无限挂起。
2. RealtimeAudioPipeline 用现有 Mutex 保护采集时长，HybridRecordingLifecycle 按音频资格判断 shouldFinalize。采集线程只记录帧数/采样率指标，无阻塞、无音频/文字日志；现有无 partial 测试补上真实有效 PCM fixture，保留其全部断言。
3. 启动标志覆盖录音及流式初始化整个过程，在初始化完成后消费待停止请求；错误路径清除待停止标志。
4. 在调用底层 stop 之前同步安装 final 订阅，以有缓冲的 AsyncThrowingStream 桥接，明确处理空 final、publisher completion、超时与取消。15 秒等待仅用于已有停止前文字的路径，保留 live 文本回退；订阅按会话释放，不记录文本。
5. 底层 stop 返回后，没有停止前 partial 时，读取停止期间已捕获的非空 final；若没有则立即取消等待及流式会话，触发 onNoResult，不额外等待 15 秒。停止失败也取消协调器。保持成功完成及粘贴行为。

## 验收与验证

- 回归测试在修复前展示具体失败，在修复后通过：录音启动期间松手、流式初始化期间松手、无结果清理并重试、同步 final 不丢失、空 final/完成/错误/取消能结束等待。
- 保留既有延迟 final、松手尾字、增量润色不阻止停止等测试；不删除或新增 skip。既有快速 live 回退 skip 属既有行为，不在本任务中改变等待策略。
- 本地使用 xcode-cli 的 SwiftPM 路线，定向测试后由正常 commit hook 执行 VoxInfrastructure 与 VoxPresentation build/test；提交后执行 `scripts/verify` 与 `scripts/verify --policy`。
- 独立计划评审 APPROVED 后，按 Owner 已授权的修复并提交请求执行；实现再做独立内容评审，正常提交、push 并按模板创建 PR，记录被测试的 head SHA，等待必需 CI。
- 不运行本地交付 build、不录制真实音频、不访问用户语音/文本；App target 与 iOS 编译验证由 PR CI 提供。

## 风险与回滚

主要风险是 Combine 回调线程、订阅生命周期以及延迟 final 被提前取消。桥接只向线程安全的 stream continuation 写入；UI 状态仍由 MainActor 更新；等待覆盖真实延迟结果，资源释放有明确边界。回滚本 PR 即可，无 API、数据或配置迁移。

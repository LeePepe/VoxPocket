# macOS 持续流式语音转写

Created: 2026-09-18

用户目标：长录音松手后不再从头上传整段音频才开始云端识别；只修改 ASR，不修改 refine。

## 用户场景与验收

### 录音期间完成大部分识别（P1）

- 配置了专用实时部署时，macOS 在录音期间持续发送规范化音频，并显示 ASR 增量结果。
- 必须用非私密合成音频证明：音频尚未发送完时已有有效识别文本；不能仅凭 WebSocket 握手或流式返回整文件结果判定成功。
- 松手后排空本次音频队列、提交余量，等待对应终稿；健康实时路径不再提交整段文件转写。
- 实时分段或 delta 只进入 live publisher；整次录音仅发布一次 final，保持既有 refine 触发契约。

### 失败与旧配置可继续使用（P1）

- 继续保留 Apple Speech 预览及现有整文件转写作为失败兜底；不额外增加 LLM 合并。
- 网络失败、配置拒绝、队列溢出、协议错误、终稿超时有固定脱敏错误，不静默丢音频；在录音结束时最多走一次原批量兜底。
- 停止/取消/重开会话隔离；旧任务不能覆盖新会话的 live/final。资源和定时任务随会话释放。
- 未提供实时部署字段时保持原行为；iOS 不启用新路径，仍保留原代码与兼容性门禁。

## 接口与隐私边界

- 复用 MicrophoneRecorder 的 PCM buffer 回调；音频线程只复制受限大小的快照，不等待网络或模型。
- 有界音频队列、后台重采样与串行发送；24 kHz / mono / PCM16。协议以目标 Azure 试验实际接受的字段为准。
- session 设置为 transcription，不创建语音助手 response，不调用 refine 或分析服务。
- endpoint/key/deployment 仅从获准运行时配置获取；不硬编码私有资源或新增全局环境变量。
- 新增可选 `azure.realtimeTranscriptionDeployment` / `AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT`，沿用已有安全校验和环境覆盖规则。
- 音频、转写、供应商消息体和凭据不进入日志/遥测；仅记录阶段、字数、耗时、实际路径与固定失败原因。
- 暂存音频只在既有应用沙箱；不改变历史录音或用户正文。不上传旧实验的私密样本。

## 验证范围

- 合成单元测试：配置/URL 约束，PCM 格式和有界队列，delta/final 顺序与去重，finish/timeout/cancel，脱敏错误及批量兜底选择。
- 真实部署：小量新合成音频，记录配置确认、首次文字、发送结束、终稿完成、字数与失败状态；不输出正文。
- 本地跑受影响层 SPM build/test 与 App 壳快速回归；App target 完整构建由 required CI 执行。
- 代码走 PR 与全部 required checks；不在本机生成/安装交付 App。用户于本轮明确授权合并后手动触发并监督 macOS TestFlight 上传。

## 分层交付

1. VoxInfrastructure：实时协议、音频适配、Hybrid ASR 接入、私密配置兼容及该层测试，独立提交。
2. App 壳：仅在 macOS 有实时配置时注入新 ASR 能力，更新空模板/说明和入口回归，独立提交。
3. VoxApplication：删除现有 live ASR 正文/原始错误日志，补充增量不触发终稿与日志脱敏测试，独立提交；不改 refine。

参考宪法 §§II–VI；refine、UI 样式、模型质量调优、个人词库、其它平台和运行时运维不在范围内。

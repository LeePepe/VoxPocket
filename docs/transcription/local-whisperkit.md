# Local WhisperKit 转录说明

## 概览

VoxPocket 默认使用 `WhisperKitTranscriber` 进行本地实时转录（`LLMAppConfig.defaultTranscriberProvider = .localWhisperKit`）。
该路径不依赖云端语音识别服务，保留 `appleSpeech` / `hybridWhisper` / `azureWhisper` 作为回退或调试选项。

## 模型下载与缓存

- 模型由 `WhisperKit.download(variant:)` 在首次启动时自动下载。
- 下载完成后实际目录会打印到日志：`Model ready at: <path>`。
- 缓存目录由 WhisperKit/Hub 管理（通常位于系统用户缓存目录下），后续启动会复用已缓存模型。

## 启动参数

`LocalWhisperKitConfig` 当前提供：

- `model`: 默认 `openai/whisper-large-v3-turbo`
- `preloadOnStart`: 默认 `true`，在转录前后台预加载模型
- `languageHint(for:)`: 从 `Locale` 映射 Whisper 语言提示（如 `zh-Hans -> zh`）

运行时行为：

- `start(language:)` 会先检查麦克风权限。
- 如果引擎尚未就绪，会等待预加载任务完成。
- 成功后开始流式转录，持续发布 partial，`stop()` 时发布 final。

## 遥测字段（最小集）

当前记录以下关键字段：

- `whisper.model.loaded`: `model`, `load_ms`
- `whisper.model.load_failed`: `model`, `reason`
- `transcription.failed`: `provider`, `model`, `phase`, `reason`
- `transcription.completed`: `provider`, `model`, `elapsed_ms`, `rtf_rough`, `text_length`

## 常见失败与排查

1. 麦克风权限未授权
- 现象：`start(language:)` 抛出“麦克风权限未授权”。
- 处理：在系统设置中给 App 打开麦克风权限后重试。

2. 模型加载失败
- 现象：启动阶段抛出模型相关错误，`isTranscribing` 保持 `false`。
- 处理：检查磁盘空间、网络、模型缓存目录权限；必要时清理缓存后重新下载。

3. 本地模块不可用
- 现象：错误包含 `WhisperKit module unavailable in current build`。
- 处理：确认构建环境包含 WhisperKit 依赖并已成功编译。

4. 启动后无结果
- 现象：无 partial/final 输出。
- 处理：确认输入设备可用、音频采集电平是否变化，以及语言参数是否匹配输入语种。

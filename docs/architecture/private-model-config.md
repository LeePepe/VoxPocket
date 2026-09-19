# 本机模型配置

用户于 2026-09-09 批准 Azure 凭据从本机私密配置读取。代码和空模板可以提交；私密文件不提交、不嵌入安装包。0600 是访问权限控制，不是加密。

## 配置位置与使用

复制仓库根目录 `config.example.json` 的结构到 App 沙箱的 `Library/Application Support/VoxPocket/config.private.json`，填写资源 HTTPS 根地址、API key、语音和精炼 deployment 名，然后设置 `chmod 600`。部署名可能不同于模型名。

macOS 当前 bundle 的实际位置：

```text
~/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/config.private.json
```

iOS 使用其应用沙箱内同一相对路径。本轮不提供 iOS 文件导入器或设置编辑器。文件修改后重启生效；普通 Finder 启动不再依赖终端环境。已有精炼服务商偏好仍保留；macOS 在“设置 → 语音与文本”选择精炼服务商，iOS 保留原“我的 → 模型服务”入口。

### macOS 分阶段模型设置

「设置 → 语音与文本」独立选择语音识别、意图分析、语气分析及文本精炼模型。
没有保存过识别选择时默认选实时流式；已有精炼服务商与跳过分析偏好保留。
模型选择在下一次录音生效，当前录音/终稿及精炼请求持有本次模型快照。
识别可切换流式云端、整段云端、Apple Speech；文本各阶段可选择 Apple Intelligence
或当前配置的 Azure 文本模型。不虚构尚未部署的模型选项。

`azure.realtimeTranscriptionDeployment` 为可选字段（省略或 `null` 不提供实时部署默认值），对应环境变量
`AZURE_REALTIME_TRANSCRIPTION_DEPLOYMENT`。也可在设置的「实时部署配置」填写非敏感部署名覆盖值，
留空使用私密配置/环境中的部署名。填写经过实时音频验证的专用 transcription 部署名，
使用同一 HTTPS 资源根地址和语音密钥。不要直接填普通文件转写模型名来猜测实时能力。
仅 macOS 使用此字段；iOS 仍使用原转写实现。

缺少实时部署或凭据时，设置页明确显示当前回退到整段云端/Apple Speech，不将默认选择视为远端验证成功。
只将模型选择及用户填写的安全部署短标识存入偏好；不复制私密配置对象、端点或 API key 到 UserDefaults。

启用后录音期间发送 24 kHz mono PCM16，Apple Speech 保留为预览备用；松手后排空并提交终稿。
连接/协议失败、音频队列溢出或收尾超过 8 秒时，至多回退一次原整文件 ASR。
只有整次录音终稿进入原精炼流程；增量文字不会逐条调用 refine。日志只记录路径与字数。
启用前需以新合成音频确认「发送结束前已有识别文字」；单元测试及连接成功不能替代这一验证。

## 边界

- SwiftUI 从同步 `main()` 启动系统事件循环；`AppStartup` 随后异步加载配置。窗口内容保持惰性，AppDelegate 的服务初始化、预热与热键注册也等待配置成功；不在主线程同步读取或等待。
- macOS 不再声明普通主窗口；菜单与 `⌘,` 打开同一 Settings Scene。历史存储在后台启动时初始化，Fn 保存等待同一次初始化完成；数据库 schema 与位置不变。
- 只读取固定沙箱路径，不搜索仓库、不搜索 bundle、不接受配置中的任意文件路径。
- 文件必须为当前用户所有的普通文件，权限 0600、大小不超过 64 KiB；拒绝符号链接和非普通文件。加载时排除系统备份。
- endpoint 必须为无用户名/密码、query、fragment 的 HTTPS 根地址；部署名只接受安全的短标识。JSON/权限/字段错误只返回固定诊断，不回显输入、密钥或解码器正文。
- 环境变量字段覆盖文件默认值，兼容旧密钥别名；不将配置写入全局环境或 UserDefaults。
- 不存在文件时保留原环境变量流程；存在但无效时展示固定错误提示并保持服务未启动，`AppStartup` 系统日志只记录固定失败状态。修正文件后重新启动，不静默使用损坏配置。
- `.gitignore` 与 XcodeGen 排除私密文件及编辑器备份；`scripts/gates/check_private_config.py` 阻止私密文件被跟踪，支持检查归档的 `.app`。秘密扫描保持启用，绝不为真实配置加 allowlist。

## 验收证据

测试覆盖文件缺失、合法配置、环境覆盖、无效 JSON、空密钥、非法 URL/部署名、权限、大小和符号链接。交付必须确认 `git ls-files` 不含私密文件、实际 `.app` 内无私密文件；运行时配置来源日志只含来源及就绪布尔值。不得把“文件存在”当作“远端调用成功”。

## 启动交互回归（2026-09-10）

异步 `@main` 在配置加载真正挂起后直接调用 `App.main()`，会让主队列任务无法继续执行；窗口能显示、部分点击有动画，但录音及热键操作不执行。入口保持同步，配置加载放在系统事件循环启动后；主窗口、设置窗口与 AppDelegate 共享加载结果。Intent 继续等待同一底层配置任务；冷启动 URL 在配置成功后交给路由。

- `python3 scripts/tests/test_startup_interaction.py` 提取生产入口，用会真正挂起的无凭据配置替身与进程内鼠标事件验证主队列、MainActor 任务和视图更新。测试不使用用户数据、麦克风或远端模型。
- `python3 scripts/tests/test_app_startup.py` 在隔离宿主中编译生产启动控制器和 App 单元测试，覆盖加载顺序、并发入口、调用者取消与失败保持。Xcode App 测试仍使用同一份测试文件。
- `python3 scripts/tests/test_menu_bar_launch.py` 验证没有主窗口时正常/失败配置均能独立打开设置。
- 以上回归同时接入 CI 的 App target 验证；本地可跑无凭据隔离宿主，但不生成交付 App 归档。交付遵循 AGENTS.md 的 TestFlight 唯一渠道与当前 macOS-only 范围。

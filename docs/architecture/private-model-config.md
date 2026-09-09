# 本机模型配置

用户于 2026-09-09 批准 Azure 凭据从本机私密配置读取。代码和空模板可以提交；私密文件不提交、不嵌入安装包。0600 是访问权限控制，不是加密。

## 配置位置与使用

复制仓库根目录 `config.example.json` 的结构到 App 沙箱的 `Library/Application Support/VoxPocket/config.private.json`，填写资源 HTTPS 根地址、API key、语音和精炼 deployment 名，然后设置 `chmod 600`。部署名可能不同于模型名。

macOS 当前 bundle 的实际位置：

```text
~/Library/Containers/com.leepepe.voxpocket/Data/Library/Application Support/VoxPocket/config.private.json
```

iOS 使用其应用沙箱内同一相对路径。本轮不提供 iOS 文件导入器或设置编辑器。文件修改后重启生效；普通 Finder 启动不再依赖终端环境。已有精炼服务商偏好仍保留，需要在“我的 → 模型服务”选择 Azure Foundry。

## 边界

- 文件读取在后台完成，并在 SwiftUI/AppDelegate/服务初始化之前完成；不在主线程同步读取或等待。
- 只读取固定沙箱路径，不搜索仓库、不搜索 bundle、不接受配置中的任意文件路径。
- 文件必须为当前用户所有的普通文件，权限 0600、大小不超过 64 KiB；拒绝符号链接和非普通文件。加载时排除系统备份。
- endpoint 必须为无用户名/密码、query、fragment 的 HTTPS 根地址；部署名只接受安全的短标识。JSON/权限/字段错误只返回固定诊断，不回显输入、密钥或解码器正文。
- 环境变量字段覆盖文件默认值，兼容旧密钥别名；不将配置写入全局环境或 UserDefaults。
- 不存在文件时保留原环境变量流程；存在但无效时阻止启动，诊断通过 `ModelConfiguration` 系统日志与 stderr 给出。修正文件后重新启动，不静默使用损坏配置。
- `.gitignore` 与 XcodeGen 排除私密文件及编辑器备份；`scripts/gates/check_private_config.py` 阻止私密文件被跟踪，支持检查归档的 `.app`。秘密扫描保持启用，绝不为真实配置加 allowlist。

## 验收证据

测试覆盖文件缺失、合法配置、环境覆盖、无效 JSON、空密钥、非法 URL/部署名、权限、大小和符号链接。交付必须确认 `git ls-files` 不含私密文件、实际 `.app` 内无私密文件；运行时配置来源日志只含来源及就绪布尔值。不得把“文件存在”当作“远端调用成功”。

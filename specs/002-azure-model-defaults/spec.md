# Azure 模型默认值与请求兼容

用户要求：默认使用已验证的 gpt-transcribe 与 gpt-5.6-luna，并确认现有 Settings 的配置能力。

## 验收

- 有完整环境配置时，Apple 提供实时预览，Azure gpt-transcribe 提供终稿。
- 默认精炼服务为 Azure Foundry；Luna 使用 v1 Chat Completions、max_completion_tokens、reasoning_effort=none。
- 已保存的用户服务商选择优先，不擅自迁移其他用户偏好；当前用户安装时可在“我的 → 模型服务”选 Azure Foundry。
- 不硬编码账户、资源地址或凭据；缺失配置有明确诊断，Azure 精炼缺配置时失败而不静默改用 Apple。
- 不为每次云端终稿强制追加 LLM 合并；用户请求的精炼行为保留。
- 云端响应错误可能包含用户正文，日志及上层错误只保留状态码等非内容指标。
- 保持旧 Foundry 请求兼容；添加新接口契约、问号保留、偏好保留及配置校验测试。

## 范围边界

本轮不新增 Settings UI、密钥存储机制、全局环境变量、自动启动任务或订阅资源。macOS 原生 General 仍是占位；应用内“我的 → 模型服务”只有精炼服务商与跳过分析开关，不支持语音模型/部署名/密钥配置。

## 启动配置

- `AZURE_OPENAI_ENDPOINT`：资源 HTTPS 根地址（不要附模型路径）。
- `AZURE_TRANSCRIPTION_DEPLOYMENT`：转写 deployment 名，缺省 `gpt-transcribe`；也可用 `AZURE_TRANSCRIPTION_ENDPOINT` 提供完整文件转写 URL。
- `AZURE_API_KEY`：进程环境中的资源密钥；转写兼容 `whisperkey`，精炼兼容已有密钥变量。
- `AZURE_FOUNDRY_MODEL`：文本 deployment 名，缺省 `gpt-5.6-luna`。
- `AZURE_FOUNDRY_ENDPOINT`：可选文本端点覆盖，缺省使用 `AZURE_OPENAI_ENDPOINT`。

部署名不必等于模型名，使用先前试验部署时必须注入它们的实际名称。Finder 启动的 App 不会自动继承 Terminal/Xcode 的环境；源码默认值修改不等于已安装应用已获得凭据。安装替换仍需用户明确要求；不能把密钥写进构建产物来解决启动配置。

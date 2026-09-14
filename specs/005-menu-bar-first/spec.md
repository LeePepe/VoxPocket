# 菜单栏优先入口（第一阶段）

用户已同意浮窗优先的产品流程，并要求继续采用 SPM + 多 Package 分层。

## 范围

- macOS 启动不主动展示/恢复主窗口；菜单栏始终提供应用入口。
- 菜单仅展示配置状态，以及打开主窗口、设置、退出操作。
- 主窗口和已有历史数据保留，菜单打开主窗口不得自动录音；FullPanel 快捷键原语义保留。
- 设置仍复用现有 Settings Scene，本阶段不迁移「我的」内容，不开放新模型/词库配置。
- Fn 录音、精炼、复制粘贴与 iOS 启动流程不变。
- 不隐藏 Dock、不修改激活策略，不新增录音状态合并或最近结果存储。

## 分层

1. VoxPresentation / PlatformUI：原生菜单视图、展示状态与注入的动作；独立 SPM 测试和提交。
2. App target：场景声明、窗口/设置打开动作和退出动作、AppStartup 状态映射；独立提交。
3. VoxApplication、VoxInfrastructure、VoxDomain 与所有 Package.swift 保持不变。

## 验收

- 正常或延迟启动时均不弹主窗口；服务初始化继续由 AppDelegate 等待配置后执行，不依赖窗口出现。
- 无需完成配置就能从菜单打开主窗口/设置，看到现有启动状态或固定错误提示，并能退出。
- “配置已加载”只表示配置加载完成，不伪装成麦克风权限、远端服务或快捷键已可用。
- 菜单打开主窗口可复用同一窗口；关闭它不退出后台应用。
- 菜单设置和应用菜单/⌘, 使用同一 Settings Scene；不新建第二套配置状态。
- 菜单文案不含用户录音、转写或私密配置内容。
- 层内 SPM build/test；无凭据场景测试与原有启动测试；完整 App-target 构建由 CI required 执行，交付仅走 TestFlight。

## 本地验证记录

- VoxPresentation：105 项测试，1 项既有跳过，0 失败。包括菜单加载/失败状态、构造不触发动作、失败态真实按钮点击和深浅色渲染。
- `test_app_startup.py`：6 项测试通过；`test_startup_interaction.py`：主队列、任务、点击和渲染检查通过。
- `test_menu_bar_launch.py`：直接编译生产 MacOSAppScenes / 菜单 / AppStartup，替换内容与配置；正常和失败配置均验证启动无主窗口、显式打开复用窗口、主窗口关闭后仍可开设置。脚本已接入 App target CI。
- 内容层设计审查 34/35，无阻断项；截图为生产菜单内容的测试宿主，不作为原生系统菜单样式或完整 App UI 验收。
- 无 Package.swift 或下层包变更；frontmatter 五层校验与私密配置防入库检查通过。
- 本轮未运行完整 xcodebuild / App XCUITest，也未归档、安装或触发 TestFlight 发布；完整 App 验证仍由 CI 执行。

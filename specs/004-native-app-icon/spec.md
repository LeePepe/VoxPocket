# Feature Specification: 原生分层三椭圆图标

**Feature Branch**: `feat/liquid-glass-app-icon`
**Created**: 2026-09-09
**Status**: Implemented; resource validation complete, full App build pending CI
**Input**: 用户批准三条共心窄椭圆与多色光谱，要求在 worktree 接入 macOS 26 图标，描边再粗一些、具备立体质感。

## User Scenarios & Testing

### User Story 1 — 原生系统图标（Priority: P1）

用户在 macOS 26 使用应用时，可看到保留已批准几何的光谱三椭圆，具有适度高光和浮雕，而不是烘焙的网页玻璃效果。

**Independent Test**: 原生 Icon Composer 渲染六种外观，编译 App 图标资源，确认资源名与 target membership。

**Acceptance Scenarios**:

1. Given 已批准的 `rx56 / ry99.12 / −60,0,+60` 母版，When 生成前景层，Then 只将描边从 5 增至 7，不改变长短轴、圆心和角度。
2. Given macOS 26 原生渲染器，When 导出 Default/Dark/Clear/Tinted，Then 图形完整、保留中心空白，彩色版本沿用五色光谱，Mono 版本仍可识别。
3. Given Xcode 项目，When 编译 iOS/macOS 图标资源，Then `.icon` 被识别并产生有效图标产物；visionOS 不加入该新资源。

### Edge Cases

- 小尺寸交叉点较密，必须独立导出 16/32/64px，不能将网页中的加粗专版冒充 `.icon` 的自动尺寸变体。
- 矢量轮廓不得含明显多边形切面；通过连续切线的曲线展开描边。
- 保留原 asset catalog，但不假设它优先于同名 `.icon`；用编译生成的 `.icns` 检查实际选择。
- 不使用 macOS 27 / Composer 2 专属折射参数。

## Requirements

- **FR-001**: 制作同名 `AppIcon.icon`，保留 `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`。
- **FR-002**: 采用三个前景层、一个效果组；原生高光和轻阴影，不预烘焙玻璃、背景遮罩或光晕。
- **FR-003**: 支持 light/dark/tinted 图层特化并输出六种 macOS 原生外观。
- **FR-004**: XcodeGen 配置与项目文件均包含正确资源及 iOS/macOS destination filters。
- **FR-005**: 几何、颜色与生成器可重建，并附无网络回归测试。

## Success Criteria

- **SC-001**: 生成一致性检查和回归测试全部通过。
- **SC-002**: macOS 26.2 与 iOS 26.2 图标资源编译通过；macOS 产出 `Assets.car`、`AppIcon.icns` 和图标 Info.plist 字段。
- **SC-003**: 六种外观 × 五种尺寸的 30 张原生 PNG 导出且尺寸正确。
- **SC-004**: 六种外观预览应无裁切、意外断线或交点破损；完整 App 构建和真实 Dock/Finder/Spotlight 的最终安装验收需另行执行。

## Scope

仅 App 壳资源、图标生成/验证工具及文档；不修改 Swift packages、运行时业务、凭据、主工作目录、安装位置或发布工作流。linked worktree 按项目规则不自动归档 App。

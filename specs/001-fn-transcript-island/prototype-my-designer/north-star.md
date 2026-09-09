# VoxPocket — my-designer 备选预览

2026-09-08。状态：独立概念稿，未替换现有 SwiftUI 实现。

## 要回答的问题

让转写文字成为视觉主角、让浮窗贴近刘海下缘，是否比当前独立卡片更自然？
按用户要求仅新增一版 B；A 使用现有版本的真实 SwiftUI 截图供对照。

## 设计契约

- my-designer 为设计负责人。遵循其 references/design-language.md。
- 单一 blue seed、Radix slate；使用原始 color-system.ts 的 buildTokens 派生。
- Flat：L0 < L1 < L2，细描边，无阴影；文字 19 / 13 / 11 三层。
- 显示识别原文；最新片段正常高对比，前文使用 secondary，长文本区域限高并跟随末尾。
- 状态用有文字的有色 pill，忙碌反馈不伪造识别进度；完成用固定 success，错误用固定 danger。
- 岛形是本项目的功能性形状例外：外轮廓 28px、紧凑态胶囊；不套 dashboard 卡片 12px 半径。
- 硬件刘海由独立的 device-ink token 表示，不作为第二套 UI 色系。
- 无数据统计需求，不插入 KPI 或无关图表；波形只演示录音音量，不声称来自麦克风。
- 深色岛在浅色桌面上下文中验证；普通显示器采用同一组件顶部留距，不显示刘海连接颈。
- 不阻挡刘海摄像头区域；具体 NSScreen 安全区、多屏定位需选中方向后再工程实现。
- 减少动态效果关闭波形与形变动画；按钮可键盘操作，识别文字可滚动。

## 预览边界

这是静态文件组成的 HTML 交互原型，不是 SwiftUI 已实现效果，不接识别、粘贴、遥测或持久化。
VoxPocket 没有 Web 路由，所以在当前功能规格旁隔离保存原型，不新增正式 App 依赖。
支持 `?variant=B`（备选）和 `?variant=A`（当前截图），仅内存模拟识别过程。
本轮没有 Figma 来源；没有调用 Figma、impeccable 或修改主程序。

## 运行

直接打开 index.html；如需重新生成色彩：`node generate-palette.mjs`。
本地服务：`python3 -m http.server 8765 --bind 127.0.0.1 --directory specs/001-fn-transcript-island/prototype-my-designer`。

## 验收

交付前由 design-reviewer 对桌面上下文截图、长文本、无刘海与错误状态独立评分（/35），解决 P0/P1。
用户只选方向；选中前不迁移到生产实现、不提交或发布。

---
layer: VoxNotificationKit
role: 独立零业务耦合的本地通知调度与用户两级作息锚点习惯学习深模块
owns:
  - Packages/VoxNotificationKit/**
depends_on: []
roles:
  Types: [HabitTimeSlot, VoxNotificationModels]
  Repo: [HabitTimeAnchorStore]
  Service: [AdaptiveTimeAnchorLearner, VoxNotificationScheduler]
gate: {build: "swift build --package-path Packages/VoxNotificationKit --explicit-target-dependency-import-check error", test: "swift test --package-path Packages/VoxNotificationKit --explicit-target-dependency-import-check error"}
test: swift test --package-path Packages/VoxNotificationKit --explicit-target-dependency-import-check error
targets: [VoxNotificationKit]
red_lines:
  - 严禁依赖 VoxDomain 或任何 VoxPocket 业务包(零外部/本地依赖,可原样迁移到任意 App)
  - 通知标题与用户文本仅驻留端侧内存与本地 UNNotificationRequest,严禁写入日志或遥测负载(宪法 IV)
  - 习惯学习持久化文件仅写端侧沙盒,且所有数值做 Winsorized 合法区间截断与有限数校验(宪法 IV/VI)
---

# VoxNotificationKit Tech Context

## 职责
`VoxNotificationKit` 是 100% 独立、零 `VoxDomain` 依赖的跨平台（iOS 26 / macOS 26 / watchOS 26 / visionOS 26）本地通知与时间习惯学习深模块（Deep Module），可原样复制到任何 Apple 平台项目使用：
- **`HabitTimeSlot` & `VoxNotificationModels` (`Types`)**：定义六大标准作息时间槽（`morning` `09:00`、`forenoon` `10:00`、`noon` `12:30`、`afternoon` `15:00`、`evening` `18:30`、`night` `20:30`）、合法时间窗、4 类锁屏/Apple Watch 快捷通知动作（`markDone`、`snooze15m`、`snooze1h`、`deferToNextAnchor`）及回流事件 `VoxNotificationActionEvent`。
- **`HabitTimeAnchorStore` (`Repo`)**：将用户的全局时段与 `(slot, #tag)` 二级习惯统计量原子持久化在端侧沙盒 `time-anchor-habits.json`。
- **`AdaptiveTimeAnchorLearner` (`Service`)**：`global_plus_tag_two_level` 两级习惯学习器，融合手动改期（$\alpha = 0.35$）、通知延后（$\alpha = 0.20$）与准点完成（$\alpha = 0.15$）三类反馈信号，经 Winsorized 合法区间截断、经验贝叶斯收缩（$\lambda = \frac{n}{n + 2}$）与 5 分钟粒度对齐，计算最佳提醒时刻并支持当日已过期时的智能次日顺延。
- **`VoxNotificationScheduler` (`Service`)**：封装 `UNUserNotificationCenter` 分类注册（`vox.notification.todo.reminder`）、4 个免解锁快捷交互动作、幂等调度/撤销以及与 `AdaptiveTimeAnchorLearner` 的自动闭环联动。

## 层内轴
`Types(HabitTimeSlot, VoxNotificationModels)` ← `Repo(HabitTimeAnchorStore)` ← `Service(AdaptiveTimeAnchorLearner, VoxNotificationScheduler)`。

---
layer: VoxDomain
role: 纯领域模型与文本历史,无外部依赖,不感知上层
depends_on: []
depended_by: [VoxInfrastructure, VoxApplication, VoxPresentation]
red_lines:
  - 禁止引入任何外部依赖或其他本地 layer(宪法 II)—— 本层是依赖链最底端
  - 模型为值类型,更新返回副本,禁止原地可变(宪法 I)
  - 不得出现平台/框架 import(SwiftUI/AppKit/Foundation-heavy 平台 API 除外的最小面)
roles:
  Types:   [CoreModels]
  Service: [TextHistory]
test: swift test --package-path Packages/VoxDomain
owns: [CoreModels, TextHistory, Checkpoint]
---

# VoxDomain Tech Context

## 职责
纯领域层(Clean Architecture 最内环)。两个 target:
- **CoreModels**:领域值类型,无依赖。
- **TextHistory**:基于 patch 的撤销/重做,通过 `Checkpoint` 快照;依赖 CoreModels。

## 数据流 / 约束
- 全部值类型,不可变更新(返回新副本)。`TextHistoryManaging` 协议定义契约。
- **红线**:本层不知道上层存在;任何 `import` 上层 layer 即违规。不引入外部 SPM 依赖
  (`Package.swift` 的 `dependencies` 必须为空)。

## 层内轴
`Types(CoreModels)` 不得依赖 `Service(TextHistory)`;`TextHistory` 依赖 `CoreModels` 合法(向下)。

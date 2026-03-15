# 本地 CI/CD 设计说明

## 背景

VoxPocket 当前以本地开发为主，工程主体是 Xcode 工程加四层 Swift Package。仓库已有明确的构建与测试入口，但缺少一套稳定、可重复执行的本地发布流程。

目标是建立一套纯本机运行的 CI/CD 机制，围绕 `main` 和 `dev` 两个长期分支工作：

- `main` 保持 stable，可作为稳定版本来源
- `dev` 承接日常开发与集成
- feature 从 `dev` 拉出，完成后回合到 `dev`
- 当 `dev` 稳定后，定期合并到 `main`
- 合并到 `main` 后自动执行本地 release pipeline

## 目标

- 用本地 `git hook + shell 脚本` 实现轻量 CI/CD
- 在 `dev -> main` merge 后自动触发发布
- 自动维护版本号，区分大版本、小版本和补丁版本
- 自动生成 changelog
- 自动整理本地发布产物目录
- 不依赖 GitHub Actions、Jenkins 或其他云/服务端 CI

## 非目标

- 不引入常驻的本地 CI 服务
- 不处理远程部署、TestFlight、App Store 发布
- 不改变现有四层包结构
- 不要求在每次开发提交时自动跑完整验证流程

## 方案选择

### 推荐方案

采用 `git hooks + 本地 shell 脚本 + releases 目录`。

原因：

- 贴合当前仓库规模和单机开发模式
- 能直接复用已有 `xcodebuild` 与 `swift test` 入口
- 配置和维护成本显著低于本地自托管 CI 服务
- 失败定位简单，产物和日志都在本地可见

### 备选方案

1. hook 只负责投递任务，真正构建由 `launchd` 执行
2. 在本地部署 Jenkins / Gitea Actions 等服务

备选方案都增加了额外维护成本，因此本阶段不采用。

## 分支模型

长期分支：

- `main`：稳定分支，只接收来自 `dev` 的定期合并
- `dev`：集成分支，承接日常开发

短期分支：

- `feature/<name>`：从 `dev` 拉出，完成后合回 `dev`
- 如需 hotfix，可从 `main` 拉出 `hotfix/<name>`，合回 `main` 后按补丁版本发布，再回合到 `dev`

约束：

- 不直接在 `main` 上做日常开发
- `main` 的发布动作仅由 merge 进入，不由普通提交触发

## 触发模型

发布自动化仅在以下条件同时满足时触发：

1. 当前分支是 `main`
2. 刚完成一次 merge
3. merge 来源是 `dev`，或显式允许的 `hotfix/*`
4. 当前工作区干净

触发方式：

- 首选 `post-merge` hook
- 必要时用辅助状态文件避免重复触发

不采用“先 verify 再 release”的双阶段模式。触发后直接进入 release pipeline。

## Release Pipeline

单次发布流程按顺序执行：

1. 校验当前分支、merge 来源和工作区状态
2. 解析当前版本号
3. 计算下一版本号
4. 更新 Xcode 工程中的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`
5. 基于上一个 tag 到当前 `HEAD` 生成 changelog
6. 构建 macOS 发布产物
7. 生成 release 元数据
8. 将产物、changelog、日志写入版本目录
9. 创建 release commit
10. 打 tag

若任一步失败：

- 立即停止流程
- 不创建 tag
- 不保留不完整的发布目录
- 不提交半成品 release commit

## 版本策略

采用两层 Xcode 原生版本字段：

- `MARKETING_VERSION`：语义化版本 `MAJOR.MINOR.PATCH`
- `CURRENT_PROJECT_VERSION`：单调递增构建号 `BUILD`

### 默认升级规则

- `dev -> main` 的常规稳定发布：默认执行 `MINOR + 1`，并将 `PATCH` 归零
  - 例如：`1.3.2 -> 1.4.0`
- `main` 上的 hotfix 发布：执行 `PATCH + 1`
  - 例如：`1.4.0 -> 1.4.1`
- 明确发生不兼容变化时：执行 `MAJOR + 1`，并将 `MINOR`、`PATCH` 归零
  - 例如：`1.4.3 -> 2.0.0`
- 每次成功发布后：`CURRENT_PROJECT_VERSION + 1`

### 升级判定建议

本阶段默认采用保守自动规则：

- `dev -> main`：默认 minor
- `hotfix/* -> main`：默认 patch
- major 升级由脚本参数或显式标记控制，不做自动猜测

## Tag 与 Changelog

tag 采用：

- `v1.4.0`
- `v1.4.1`

changelog 基于最近一个 release tag 到当前 `HEAD` 的 commit 生成，优先识别 conventional commits：

- `feat:` 归入 Features
- `fix:` 归入 Fixes
- `refactor:`、`test:`、`docs:` 归入 Maintenance 或 Others

changelog 文件同时写入：

- 当前 release 目录下的 `CHANGELOG.md`
- 可选地汇总到仓库根级发布历史文件

## 产物目录

新增本地发布目录：

```text
releases/
  v1.4.0/
    CHANGELOG.md
    release.json
    build.log
    artifacts/
      VoxPocket.app
```

说明：

- `CHANGELOG.md`：给人阅读
- `release.json`：保存版本、tag、commit、时间、build 号、产物路径
- `build.log`：记录构建输出，便于失败排查
- `artifacts/`：保存实际构建产物

## 仓库结构调整

计划新增以下结构：

```text
.githooks/
  post-merge

scripts/
  ci/
    common.sh
    release.sh
    version.sh
    changelog.sh
    build.sh

releases/

docs/
  local-cicd.md
```

职责划分：

- `.githooks/post-merge`：检测是否满足自动发布条件，满足则调用统一入口
- `scripts/ci/release.sh`：串联整个发布流程
- `scripts/ci/version.sh`：读取并更新版本号
- `scripts/ci/changelog.sh`：生成 changelog
- `scripts/ci/build.sh`：执行构建并导出产物
- `scripts/ci/common.sh`：日志、路径、清理和错误处理

## 失败处理

失败策略如下：

- 任一步报错即退出，退出码向上传递给 hook
- 临时目录放在 `.tmp` 或系统临时目录，失败时清理
- release 目录只有在流程成功后才原子性落盘
- tag 只在 release commit 成功后创建
- 如脚本需要修改工程文件，应确保在 release commit 前没有其他未跟踪副作用

## 日常工作流

### 日常开发

1. 从 `dev` 拉出 `feature/<name>`
2. 开发完成后合回 `dev`
3. `dev` 持续累积待发布内容

### 稳定发布

1. 切换到 `main`
2. 执行 `git merge dev`
3. `post-merge` 自动触发 release pipeline
4. 成功后产出新版本号、新 tag 和本地发布目录

### Hotfix

1. 从 `main` 拉出 `hotfix/<name>`
2. 修复后合回 `main`
3. 自动执行 patch release
4. 再将修复回合到 `dev`

## 测试与验证建议

实现阶段至少应覆盖：

- 版本计算脚本单元测试
- changelog 生成逻辑测试
- merge 来源识别测试
- 非 `main` 分支不触发测试
- 工作区不干净时拒绝发布测试
- 成功发布后目录结构校验

构建阶段验证：

- `xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build`
- 受影响的 Swift Package 测试命令

## 风险与约束

- `post-merge` 中执行完整构建会拉长 merge 完成时间
- 若 Xcode 签名或本地环境状态变化，release 成功率依赖当前机器配置
- changelog 质量依赖 commit message 规范性
- 自动改版本号并提交 release commit，意味着 `main` merge 后会额外产生一条提交；需要在团队习惯上接受这一点

## 后续实现建议

实现顺序建议为：

1. 先完成版本与 changelog 脚本
2. 再完成构建与 release 目录产物整理
3. 最后接入 `post-merge` hook
4. 增加文档，说明如何启用本地 hooks

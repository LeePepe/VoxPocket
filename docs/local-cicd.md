# 本地 CI/CD 使用说明

这套流程只在本地运行，不依赖 GitHub Actions、Jenkins 或其他远程 CI。

## 分支约定

- `main`：稳定分支，只保留 stable 版本
- `dev`：日常开发和集成分支
- `feature/*`：从 `dev` 拉出，完成后合回 `dev`
- `hotfix/*`：从 `main` 拉出，修复后合回 `main`，再回合到 `dev`

推荐节奏：

1. 从 `dev` 创建 `feature/*`
2. feature 合回 `dev`
3. `dev` 稳定后合并到 `main`
4. `main` merge 完成后本地 hook 自动发版

## 版本规则

- `MARKETING_VERSION` 使用 `MAJOR.MINOR.PATCH`
- `CURRENT_PROJECT_VERSION` 使用单调递增的 build number

默认升级规则：

- `dev -> main`：`minor + 1`，同时 `patch` 归零
- `hotfix/* -> main`：`patch + 1`
- `major` 升级保留给手动触发或后续扩展

## 启用 Hook

在仓库根目录执行：

```bash
zsh scripts/ci/install-hooks.sh
```

它会配置：

```bash
git config core.hooksPath .githooks
```

## 自动发布触发条件

`post-merge` 只在以下情况下触发 release：

- 当前分支是 `main`
- 最新提交是 merge commit
- merge 来源是 `dev` 或 `hotfix/*`
- 工作区是干净的

非这些情况会直接退出，不会打断日常 checkout 或 pull。

## 发布产物

发布成功后会在本地生成：

```text
releases/
  vX.Y.Z/
    CHANGELOG.md
    release.json
    build.log
    artifacts/
      VoxPocket.app
```

`releases/` 是本地产物目录，默认被 `.gitignore` 忽略，不参与提交。

## 手动运行

如果你想跳过 hook，直接执行：

```bash
zsh scripts/ci/release.sh main dev
```

或者让脚本自行从当前 merge commit 检测来源：

```bash
zsh scripts/ci/release.sh --auto
```

## 测试与验证

跑脚本测试：

```bash
zsh scripts/ci/tests/test_runner.sh
```

验证 app 构建：

```bash
xcodebuild -project VoxPocket/VoxPocket.xcodeproj -scheme VoxPocket build
```

## 脚本结构

- `scripts/ci/release.sh`：release 总入口
- `scripts/ci/version.sh`：版本读取、计算、写回
- `scripts/ci/trigger.sh`：分支和 merge 来源判定
- `scripts/ci/changelog.sh`：changelog 生成
- `scripts/ci/build.sh`：构建与产物收集
- `scripts/ci/release_metadata.sh`：release 目录和 metadata 写入
- `.githooks/post-merge`：merge 后自动触发入口

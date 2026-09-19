# VoxPocket GitHub 身份规则

Last-Reviewed: 2026-09-19

由 `AGENTS.md` → GitHub 身份强制引用；以下规则适用于仓库内所有原生 Git / gh 操作与命令示例，不因拆分文档而缩小范围。

## GitHub 身份（原生 Git / gh）

- 本个人仓库：`LeePepe/VoxPocket`（ID `1197276028`）；Git 与 gh 的预期认证账号均为 `LeePepe`。提交署名不是认证。
- 当前 GitHub remote：`origin`。新 clone/worktree/Multica checkout 须重新核对实际 fetch/push URL；
  本地 origin、其他 fork/upstream 或未知归属不能套用本账号，先问 Owner。
- gh 使用 `$HOME/.config/github-identity/profiles/LeePepe` 的独立无凭据 profile，复用已有 keyring。
  本文所有 gh 命令（含其他章节示例）均加下列调用前缀；仓库命令显式 `--repo LeePepe/VoxPocket`，
  API 显式指定 host/仓库路径。`--repo` 不会选择账号；共享配置中不使用 `gh auth switch`。
- 本仓库已指定账号/profile：每次 gh 调用直接用 `env -u GH_TOKEN -u GITHUB_TOKEN` 排除环境覆盖，
  无需确认被排除变量的来源，也不因其存在暂停。只影响该子进程，不读取或输出 token，不改父环境或凭据。
  profile 不可用或核验失败时停止，不回退到环境 token 或共享默认账号；核验通过即按既有任务授权继续。
  每次写前用同一 profile 核对 `/user` 的 login、仓库 full_name/ID 与所需权限，
  任一不符立即停止。凭据登录/生成/轮换、服务重启交 Owner，不进入自动恢复流程。
- 当前 checkout 或新工作区首次使用前检查 Git 的有效认证配置。以下原生配置仅在目标已核验、旧 helper
  无冲突后应用；保留旧值用于回滚，不改全局 Git、署名或 hooks。启用独立 config.worktree 时检查覆盖，
  需要只影响该工作区则用 `--worktree`；AGENTS 不会自动安装 local config。

```bash
# 原生 gh 调用形状；先检查 /user，再同前缀检查 repos/LeePepe/VoxPocket 的 id/full_name/permissions。
env -u GH_TOKEN -u GITHUB_TOKEN -u GH_REPO -u GH_HOST \
  GH_CONFIG_DIR="$HOME/.config/github-identity/profiles/LeePepe" \
  gh api --hostname github.com user --jq .login

# HTTPS 目标路径级 Git helper；已有不同 helper、pushurl、URL rewrite 或 HTTP 认证覆盖时先停下来核对。
git config --local credential.https://github.com.useHttpPath true
git config --local --replace-all credential.https://github.com/LeePepe/VoxPocket.git.helper ''
git config --local --add credential.https://github.com/LeePepe/VoxPocket.git.helper \
  '!env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/github-identity/profiles/LeePepe" gh auth git-credential'
git config --local credential.https://github.com/LeePepe/VoxPocket.git.username LeePepe
```

只读验证使用 `git ls-remote <已核验 remote> HEAD`；不要打印 `git credential fill` 或 `gh auth token`
的输出。核验通过后才执行获授权的原生 `git push` / `gh pr …`，不把只读权限检查当成写入成功。

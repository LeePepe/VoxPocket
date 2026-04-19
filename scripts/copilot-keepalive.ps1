<#
.SYNOPSIS
    GitHub Copilot Token 保活脚本 (烧香)
.DESCRIPTION
    定期刷新 Copilot token，防止过期。
    支持自动续期和简单的 chat completions 心跳请求。
.PARAMETER GitHubToken
    GitHub Personal Access Token (需要 copilot 权限)
.PARAMETER IntervalMinutes
    刷新间隔（分钟），默认 25 分钟（token 通常 30 分钟过期）
.PARAMETER Heartbeat
    是否发送心跳请求（一个简单的 chat completion 调用）
.EXAMPLE
    .\copilot-keepalive.ps1 -GitHubToken "ghp_xxxx"
    .\copilot-keepalive.ps1 -GitHubToken "ghp_xxxx" -IntervalMinutes 20 -Heartbeat
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,

    [int]$IntervalMinutes = 25,

    [switch]$Heartbeat
)

# ── 配色 ──────────────────────────────────────────────
function Write-Status  { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor DarkGray; Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok      { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor DarkGray; Write-Host "✓ $Msg" -ForegroundColor Green }
function Write-Err     { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor DarkGray; Write-Host "✗ $Msg" -ForegroundColor Red }
function Write-Warn    { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor DarkGray; Write-Host "⚠ $Msg" -ForegroundColor Yellow }

# ── Banner ────────────────────────────────────────────
Write-Host ""
Write-Host "  🔥 Copilot Token 保活 (烧香模式)" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── 获取 GitHub Token ─────────────────────────────────
if (-not $GitHubToken) {
    # 尝试从环境变量读取
    $GitHubToken = $env:GITHUB_TOKEN
}
if (-not $GitHubToken) {
    # 尝试从 gh CLI 读取
    try {
        $GitHubToken = (gh auth token 2>$null)
    } catch {}
}
if (-not $GitHubToken) {
    Write-Err "未找到 GitHub Token。请通过以下方式之一提供："
    Write-Host "  1. 参数: .\copilot-keepalive.ps1 -GitHubToken 'ghp_xxx'" -ForegroundColor Gray
    Write-Host "  2. 环境变量: `$env:GITHUB_TOKEN = 'ghp_xxx'" -ForegroundColor Gray
    Write-Host "  3. 安装 gh CLI 并登录: gh auth login" -ForegroundColor Gray
    exit 1
}

Write-Ok "GitHub Token 已获取 (****$(($GitHubToken).Substring([Math]::Max(0, $GitHubToken.Length - 4))))"

# ── 全局状态 ──────────────────────────────────────────
$script:CopilotToken = $null
$script:TokenExpiry   = [DateTime]::MinValue
$script:RefreshCount  = 0
$script:ErrorCount    = 0

# ── 获取 Copilot Token ────────────────────────────────
function Get-CopilotToken {
    try {
        $headers = @{
            "Authorization" = "token $GitHubToken"
            "Accept"        = "application/json"
            "User-Agent"    = "GithubCopilot/1.0"
        }

        $response = Invoke-RestMethod `
            -Uri "https://api.github.com/copilot_internal/v2/token" `
            -Headers $headers `
            -Method Get `
            -ErrorAction Stop

        $script:CopilotToken = $response.token
        # 解析过期时间（Unix timestamp）
        if ($response.expires_at) {
            $script:TokenExpiry = [DateTimeOffset]::FromUnixTimeSeconds($response.expires_at).LocalDateTime
        } else {
            # 默认 30 分钟后过期
            $script:TokenExpiry = (Get-Date).AddMinutes(30)
        }
        $script:RefreshCount++
        return $true
    }
    catch {
        $script:ErrorCount++
        Write-Err "获取 Copilot Token 失败: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -eq 401) {
                Write-Err "GitHub Token 无效或已过期，请检查"
            } elseif ($statusCode -eq 403) {
                Write-Err "无 Copilot 访问权限，请确认订阅状态"
            }
        }
        return $false
    }
}

# ── 心跳请求 ──────────────────────────────────────────
function Send-Heartbeat {
    if (-not $script:CopilotToken) { return $false }

    try {
        $headers = @{
            "Authorization"       = "Bearer $($script:CopilotToken)"
            "Content-Type"        = "application/json"
            "Accept"              = "application/json"
            "Editor-Version"      = "vscode/1.100.0"
            "Editor-Plugin-Version" = "copilot/1.0.0"
            "User-Agent"          = "GithubCopilot/1.0"
            "Copilot-Integration-Id" = "vscode-chat"
        }

        $body = @{
            model    = "gpt-4o"
            messages = @(
                @{ role = "user"; content = "hi" }
            )
            max_tokens = 1
            stream     = $false
        } | ConvertTo-Json -Depth 5

        $response = Invoke-RestMethod `
            -Uri "https://api.githubcopilot.com/chat/completions" `
            -Headers $headers `
            -Method Post `
            -Body $body `
            -ErrorAction Stop

        return $true
    }
    catch {
        Write-Warn "心跳请求失败: $($_.Exception.Message)"
        return $false
    }
}

# ── Token 信息展示 ────────────────────────────────────
function Show-TokenInfo {
    $remaining = ($script:TokenExpiry - (Get-Date))
    $remainingStr = "{0:D2}:{1:D2}" -f [int]$remaining.TotalMinutes, $remaining.Seconds
    Write-Status "Token 有效期剩余: $remainingStr | 已刷新: $($script:RefreshCount) 次 | 错误: $($script:ErrorCount) 次"
}

# ── 主循环 ────────────────────────────────────────────
Write-Status "刷新间隔: $IntervalMinutes 分钟 | 心跳: $(if ($Heartbeat) {'开启'} else {'关闭'})"
Write-Host ""

# 首次获取
Write-Status "正在获取初始 Copilot Token..."
if (-not (Get-CopilotToken)) {
    Write-Err "初始 Token 获取失败，退出"
    exit 1
}
Write-Ok "Token 获取成功！过期时间: $($script:TokenExpiry.ToString('yyyy-MM-dd HH:mm:ss'))"

if ($Heartbeat) {
    Write-Status "发送初始心跳..."
    if (Send-Heartbeat) {
        Write-Ok "心跳成功"
    }
}

Write-Host ""
Write-Host "  🕯️  烧香中... (Ctrl+C 退出)" -ForegroundColor Yellow
Write-Host ""

# 持续刷新循环
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($true) {
        # 显示状态
        Show-TokenInfo

        # 等待到下一次刷新
        $sleepSeconds = $IntervalMinutes * 60
        # 每 30 秒显示一次状态
        $elapsed = 0
        while ($elapsed -lt $sleepSeconds) {
            $chunk = [Math]::Min(30, $sleepSeconds - $elapsed)
            Start-Sleep -Seconds $chunk
            $elapsed += $chunk

            # 检查 token 是否即将过期（5 分钟内）
            $remaining = ($script:TokenExpiry - (Get-Date)).TotalMinutes
            if ($remaining -lt 5) {
                Write-Warn "Token 即将过期 ($([int]$remaining) 分钟)，提前刷新"
                break
            }

            if ($elapsed -lt $sleepSeconds) {
                Show-TokenInfo
            }
        }

        # 刷新 Token
        Write-Host ""
        Write-Status "🔄 刷新 Token..."
        if (Get-CopilotToken) {
            Write-Ok "Token 刷新成功！过期时间: $($script:TokenExpiry.ToString('HH:mm:ss'))"
        } else {
            Write-Warn "刷新失败，60 秒后重试..."
            Start-Sleep -Seconds 60
            if (-not (Get-CopilotToken)) {
                Write-Err "连续刷新失败，请检查网络和 Token"
            }
        }

        # 心跳
        if ($Heartbeat) {
            Write-Status "💓 发送心跳..."
            if (Send-Heartbeat) {
                Write-Ok "心跳成功"
            }
        }

        # 运行时间统计
        $uptime = $stopwatch.Elapsed
        Write-Status "已运行: $($uptime.Hours)h $($uptime.Minutes)m | 总刷新: $($script:RefreshCount) 次"
        Write-Host ""
    }
}
finally {
    $stopwatch.Stop()
    Write-Host ""
    Write-Warn "烧香结束。总运行: $($stopwatch.Elapsed.Hours)h $($stopwatch.Elapsed.Minutes)m | 刷新: $($script:RefreshCount) 次"
}

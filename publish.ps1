#Requires -Version 5.1
<#
    publish.ps1  ——  把本仓库推到你的 GitHub

    为什么需要你亲自跑一下？
      因为发布到 GitHub 需要你的账号授权，而这是脚本不该替你做的事：
        - 读你已保存的凭据 —— 安全策略不允许
        - 让你把 token 贴给我 —— 那是密钥，不该出现在对话里

      所以最后这一步，只能你点一下。

    跑法（任选一种）：
      1. 右键这个文件 -> "使用 PowerShell 运行"
      2. 在终端里：
           powershell -ExecutionPolicy Bypass -File .\publish.ps1

    前提：
      - 你已经在 https://github.com/new 建了一个空仓库，名字叫 mouse-and-eyes
        （不要勾 "Add a README file"，否则 push 会被拒绝）
#>

$ErrorActionPreference = 'Stop'
$repoName = 'mouse-and-eyes'
$root = Split-Path -Parent $PSScriptRoot

Write-Host ''
Write-Host '=== 发布 mouse-and-eyes 到 GitHub ===' -ForegroundColor Cyan
Write-Host ''

# ── 1. 检查 git ──
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Host '没找到 git。先装一个：https://git-scm.com/download/win' -ForegroundColor Red
    exit 1
}

# ── 2. 问用户名 ──
Write-Host '你的 GitHub 用户名是什么？（用户名，不是邮箱）'
Write-Host '比如 https://github.com/abc123 里，就填 abc123' -ForegroundColor DarkGray
$user = Read-Host '用户名'
if ([string]::IsNullOrWhiteSpace($user)) {
    Write-Host '没填用户名，退出。' -ForegroundColor Red
    exit 1
}
$user = $user.Trim()

# ── 3. 确认仓库已经建好 ──
Write-Host ''
Write-Host "即将推送到： https://github.com/$user/$repoName" -ForegroundColor Yellow
Write-Host '如果你还没建这个空仓库，现在去 https://github.com/new' -ForegroundColor DarkGray
Write-Host '  - Repository name 填 mouse-and-eyes' -ForegroundColor DarkGray
Write-Host '  - 选 Public（这样别人才能改）' -ForegroundColor DarkGray
Write-Host '  - 不要勾 Add a README / .gitignore / license' -ForegroundColor DarkGray
Write-Host ''
$go = Read-Host '建好了吗？输入 y 继续，其它键退出'
if ($go -ne 'y' -and $go -ne 'Y') {
    Write-Host '退出。' -ForegroundColor DarkGray
    exit 0
}

# ── 4. 配置 remote ──
$remoteUrl = "https://github.com/$user/$repoName.git"
$existing = & git -C $root remote 2>$null
if ($existing -contains 'origin') {
    & git -C $root remote set-url origin $remoteUrl
    Write-Host "已更新 remote: $remoteUrl" -ForegroundColor DarkGray
}
else {
    & git -C $root remote add origin $remoteUrl
    Write-Host "已添加 remote: $remoteUrl" -ForegroundColor DarkGray
}

# ── 5. 推送 ──
Write-Host ''
Write-Host '开始推送……' -ForegroundColor Cyan
Write-Host '如果弹出登录窗口，选 "Sign in with your browser" 授权一下就行。' -ForegroundColor DarkGray
Write-Host ''

& git -C $root push -u origin main
$code = $LASTEXITCODE

Write-Host ''
if ($code -eq 0) {
    Write-Host '推送成功。' -ForegroundColor Green
    Write-Host ''
    Write-Host "仓库地址: https://github.com/$user/$repoName" -ForegroundColor Cyan
    Write-Host '打一个版本标签（发布用）:'
    Write-Host ''
    Write-Host "    git -C `"$root`" tag -a v1.0.0 -m `"v1.0.0 - first release`"" -ForegroundColor Gray
    Write-Host "    git -C `"$root`" push origin v1.0.0" -ForegroundColor Gray
    Write-Host ''
    Write-Host '或者在 GitHub 网页的 Releases 里点 "Draft a new release" 也行。' -ForegroundColor DarkGray
}
else {
    Write-Host "推送失败（退出码 $code）。常见原因：" -ForegroundColor Red
    Write-Host '  - 仓库还没在 GitHub 上创建' -ForegroundColor Gray
    Write-Host '  - 建仓库时勾了 README（远程已有提交，先 pull 或者删掉重建）' -ForegroundColor Gray
    Write-Host '  - 登录没授权成功，重跑一次本脚本' -ForegroundColor Gray
    exit $code
}

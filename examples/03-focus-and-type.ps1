#Requires -Version 5.1
<#
    示例 3：把一个窗口搬到前台，然后在里面打字（支持中文）

    这一节把三个原语连起来：
        找窗口（Window） -> 抢前台（Window） -> 输入（Input）

    ⚠️ 这个例子会真的往记事本里写字。
       所以它自己先把记事本打开、写完不保存、再关掉，全程不碰你自己的文档。

    跑法：
        powershell -ExecutionPolicy Bypass -File .\examples\03-focus-and-type.ps1
#>

. "$PSScriptRoot\..\win\Window.ps1"
. "$PSScriptRoot\..\win\Input.ps1"
. "$PSScriptRoot\..\win\Wait.ps1"

# ── 1. 打开一个记事本（用它当靶子，不碰你的文件）──
Write-Host "打开记事本..."
$notepad = Start-Process notepad.exe -PassThru

# ── 2. 等它的窗口真出现（不要用 Start-Sleep 猜时间）──
$win = Wait-Window -ProcessName 'notepad' -TimeoutMs 8000
if (-not $win) {
    Write-Host "记事本没起来，放弃。"
    Stop-Process -Id $notepad.Id -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "拿到窗口: $($win.Title)  (句柄 $($win.Handle))"

# ── 3. 搬前台，并且验证真的搬上来了 ──
[void](Set-WindowForeground -Handle $win.Handle)
if (-not (Wait-WindowForeground -Handle $win.Handle -TimeoutMs 2000)) {
    Write-Host "抢前台失败 —— 这在 Windows 上很常见，可以试试先 Set-WindowTopmost。"
}
else {
    Write-Host "已在前台。"
}

# ── 4. 点一下编辑区，确保输入焦点在里面 ──
# 窗口内坐标 (60, 60) 大致落在正文区
$p = ConvertTo-ScreenPoint -Handle $win.Handle -X 60 -Y 60
Invoke-Click -X $p.X -Y $p.Y
Start-Sleep -Milliseconds 200

# ── 5. 打字。中文必须走 SendInput，不能用 keybd_event ──
Send-UnicodeText -Text "Hello from Win32.`n"
Send-UnicodeText -Text "这一行是中文，走的是 SendInput + KEYEVENTF_UNICODE。`n"
Send-UnicodeText -Text "今天是 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Start-Sleep -Milliseconds 300

# ── 6. 收尾：不保存，直接关掉 ──
Write-Host "收尾：不保存，关掉记事本。"
Set-ClipboardText ''   # 顺手把剪贴板清一下（可选）
$notepad.CloseMainWindow() | Out-Null
Start-Sleep -Milliseconds 600
if (-not $notepad.HasExited) {
    # 可能会弹「是否保存」，直接杀掉最省事
    Stop-Process -Id $notepad.Id -ErrorAction SilentlyContinue
}
Write-Host "完成。"

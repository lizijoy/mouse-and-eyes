#Requires -Version 5.1
<#
    Window.ps1  ——  原语 2：找

    要操作一个程序，先得找到它的窗口。Windows 的窗口是一个树，
    EnumWindows 给你的是"顶层窗口"这一层（每个带标题栏的程序一个）。

    这里面最有价值的一段是 Set-WindowForeground —— 也就是"抢前台"。

    为什么抢前台这么难？
      因为 Windows 有一条不成文的规矩（前台锁）：
      后台程序不能随便把窗口顶到最前面，否则就会变成弹窗炸弹。
      所以 SetForegroundWindow 经常"返回成功但其实没生效"。

    通用解法是 AttachThreadInput：
      把自己线程的输入队列，临时挂到"当前前台窗口所属线程"上。
      挂上之后，系统认为你就是前台线程的兄弟，于是允许你切窗口。
      切完立刻断开，不然会污染别人的输入状态。
#>

. "$PSScriptRoot\Native.ps1"

# ─────────────────────────────────────────────────────────────
# 枚举
# ─────────────────────────────────────────────────────────────
function Get-Windows {
    <#
    .SYNOPSIS
        列出所有可见的顶层窗口。
    .DESCRIPTION
        每个窗口返回：句柄、标题、类名、进程 ID/名、窗口矩形。
    .PARAMETER IncludeUntitled
        默认跳过没有标题的窗口（多半是隐藏的工具窗）。
    .EXAMPLE
        Get-Windows | Where-Object ProcessName -eq 'notepad' | Format-Table
    #>
    param([switch]$IncludeUntitled)

    # 枚举本身在 C# 里完成（理由见 Native.ps1 里的注释），
    # 这边只负责把进程名补上、整理成好用的对象。
    $raw = [GuiAutoNative]::ListWindows($IncludeUntitled.IsPresent)
    if (-not $raw -or $raw.Count -eq 0) { return @() }

    # 同一个进程会有多个窗口，进程名查一次就够
    $procCache = @{}
    foreach ($w in $raw) {
        if (-not $procCache.ContainsKey($w.ProcessId)) {
            try { $procCache[$w.ProcessId] = (Get-Process -Id $w.ProcessId -ErrorAction Stop).ProcessName }
            catch { $procCache[$w.ProcessId] = '?' }
        }
    }

    $list = foreach ($w in $raw) {
        [pscustomobject]@{
            Handle      = $w.Handle
            Title       = $w.Title
            Class       = $w.ClassName
            ProcessId   = $w.ProcessId
            ProcessName = $procCache[$w.ProcessId]
            Rect        = $w
            Left        = $w.Left
            Top         = $w.Top
            Width       = $w.Width
            Height      = $w.Height
        }
    }

    return $list
}

# ─────────────────────────────────────────────────────────────
# 查找
# ─────────────────────────────────────────────────────────────
function Find-Window {
    <#
    .SYNOPSIS
        按标题 / 类名 / 进程名找一个窗口，返回第一个匹配。
    .PARAMETER TitleLike
        标题包含这段文字（不区分大小写）。
    .PARAMETER ClassLike
        窗口类名（例如 Chrome_WidgetWin_1、Notepad）。
    .PARAMETER ProcessName
        进程名，不带 .exe（例如 notepad、UGREEN NAS）。
    .PARAMETER Exact
        标题必须完全相等，而不是包含。
    .EXAMPLE
        Find-Window -TitleLike '记事本'
        Find-Window -ProcessName 'notepad'
    .NOTES
        找不到返回 $null。要等窗口出现请用 Wait.ps1 的 Wait-Window。
    #>
    param(
        [string]$TitleLike,
        [string]$ClassLike,
        [string]$ProcessName,
        [switch]$Exact
    )

    $all = Get-Windows
    $hit = $all | Where-Object {
        $ok = $true
        if ($TitleLike) {
            if ($Exact) { $ok = $ok -and ($_.Title -eq $TitleLike) }
            else        { $ok = $ok -and ($_.Title -like "*$TitleLike*") }
        }
        if ($ClassLike) { $ok = $ok -and ($_.Class -like "*$ClassLike*") }
        if ($ProcessName) { $ok = $ok -and ($_.ProcessName -like $ProcessName) }
        $ok
    } | Select-Object -First 1

    return $hit
}

# ─────────────────────────────────────────────────────────────
# 搬前台
# ─────────────────────────────────────────────────────────────
function Set-WindowForeground {
    <#
    .SYNOPSIS
        把窗口切到前台（绕过 Windows 的前台锁）。
    .PARAMETER Handle
        窗口句柄。
    .PARAMETER Restore
        如果窗口最小化了，先还原（默认开启）。
    .EXAMPLE
        $w = Find-Window -ProcessName 'notepad'
        Set-WindowForeground -Handle $w.Handle
    .NOTES
        返回 $true 只代表 API 调用没报错，不代表窗口真的到了前台。
        真要确认，切完之后比较 (GetForegroundWindow) 是不是它。
    #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [switch]$NoRestore
    )

    if (-not $NoRestore -and [GuiAutoNative]::IsIconic($Handle)) {
        [void][GuiAutoNative]::ShowWindow($Handle, 9)   # SW_RESTORE
        Start-Sleep -Milliseconds 200
    }

    $fgWindow = [GuiAutoNative]::GetForegroundWindow()
    $fgPid = 0
    $fgThread = [GuiAutoNative]::GetWindowThreadProcessId($fgWindow, [ref]$fgPid)
    $myThread = [GuiAutoNative]::GetCurrentThreadId()

    $attached = $false
    try {
        if ($fgThread -ne $myThread) {
            $attached = [GuiAutoNative]::AttachThreadInput($myThread, $fgThread, $true)
        }
        [void][GuiAutoNative]::BringWindowToTop($Handle)
        $ok = [GuiAutoNative]::SetForegroundWindow($Handle)
    }
    finally {
        if ($attached) {
            [void][GuiAutoNative]::AttachThreadInput($myThread, $fgThread, $false)
        }
    }

    return $ok
}

function Test-WindowForeground {
    <#
    .SYNOPSIS
        确认某个窗口现在是不是前台。
    .NOTES
        抢前台之后一定要验一次 —— 这是经验之谈：
        SetForegroundWindow 假成功的概率不低，不验就会在错误的窗口上乱点。
    #>
    param([Parameter(Mandatory)][IntPtr]$Handle)
    return ([GuiAutoNative]::GetForegroundWindow() -eq $Handle)
}

# ─────────────────────────────────────────────────────────────
# 置顶 / 取消置顶
# ─────────────────────────────────────────────────────────────
function Set-WindowTopmost {
    <#
    .SYNOPSIS
        把窗口钉在最上层（或解除）。
    .DESCRIPTION
        比抢前台更"硬"：置顶的窗口永远盖住其他窗口。
        适合"我要操作它，又怕被别的窗口挡住"的场合。
        用完记得解除，不然会一直压着别人。
    .EXAMPLE
        Set-WindowTopmost -Handle $h -On
        ... 操作 ...
        Set-WindowTopmost -Handle $h -Off
    #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [switch]$On,
        [switch]$Off
    )

    if ($On -or -not $Off) {
        $target = [GuiAutoNative]::HWND_TOPMOST
    }
    else {
        $target = [GuiAutoNative]::HWND_NOTOPMOST
    }

    $flags = [GuiAutoNative]::SWP_NOMOVE -bor [GuiAutoNative]::SWP_NOSIZE
    return [GuiAutoNative]::SetWindowPos($Handle, $target, 0, 0, 0, 0, $flags)
}

# ─────────────────────────────────────────────────────────────
# 窗口内坐标 -> 屏幕坐标
# ─────────────────────────────────────────────────────────────
function ConvertTo-ScreenPoint {
    <#
    .SYNOPSIS
        把"窗口内相对坐标"换算成"屏幕绝对坐标"。
    .DESCRIPTION
        鼠标 API 用的是屏幕绝对坐标，而截图通常是相对窗口的。
        这个函数就是两者之间的桥。
    .PARAMETER Handle
        窗口句柄。
    .PARAMETER X / Y
        相对于窗口左上角的坐标（含标题栏和边框）。
    .EXAMPLE
        $p = ConvertTo-ScreenPoint -Handle $h -X 100 -Y 50
        Invoke-Click -X $p.X -Y $p.Y
    #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )

    $rect = [GuiAutoNative]::WindowRect($Handle)
    return [pscustomobject]@{
        X = $rect.Left + $X
        Y = $rect.Top + $Y
    }
}

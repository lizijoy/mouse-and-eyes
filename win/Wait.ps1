#Requires -Version 5.1
<#
    Wait.ps1  ——  原语 5：等

    这一条最容易被初学者忽略，但它是「脚本能不能稳定跑」的分水岭。

    GUI 自动化失败，八成不是找错了地方，而是"找得太早"：
      点了按钮，界面还没出来就去截下一张图，截到的是旧画面；
      然后你在旧画面上找新元素，当然找不到。

    所以正确姿势不是 Start-Sleep 500（猜一个魔法数字），
    而是：轮询直到某个条件成立，或者超时报错。

    Wait-Until 就是这个模式的通用形态 —— 你传一个判断函数进去。
#>

. "$PSScriptRoot\Native.ps1"

function Wait-Until {
    <#
    .SYNOPSIS
        反复执行一个判断，直到它为 $true，或超时。
    .PARAMETER Condition
        一个脚本块，返回 $true 表示"好了"。
    .PARAMETER TimeoutMs
        最多等多久，默认 10 秒。
    .PARAMETER IntervalMs
        每两次检查之间隔多久，默认 200 毫秒。
    .PARAMETER Description
        超时错误信息里显示的名字，方便定位是哪一步失败。
    .OUTPUTS
        成功返回 $true，超时返回 $false（不抛异常，让你自己决定要不要报错）。
    .EXAMPLE
        # 等窗口标题里出现「完成」
        $ok = Wait-Until -TimeoutMs 15000 -Description '任务完成' -Condition {
            $t = (Find-Window -ProcessName 'notepad')
            $t -and $t.Title -like '*完成*'
        }
    .NOTES
        条件脚本块在每次检查时都会重新执行，所以里面要重新"看"一次当前状态，
        不要在外面算好一个值传进来（那样永远是同一张旧照片）。
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [int]$TimeoutMs = 10000,
        [int]$IntervalMs = 200,
        [string]$Description = 'condition'
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $result = $false
        try {
            $result = [bool](& $Condition)
        }
        catch {
            $result = $false      # 条件里抛异常就当"还没好"，继续等
        }

        if ($result) { return $true }
        Start-Sleep -Milliseconds $IntervalMs
    }

    if ($Description) {
        Write-Verbose ("等待超时（{0} 毫秒）：{1}" -f $TimeoutMs, $Description)
    }
    return $false
}

function Wait-Window {
    <#
    .SYNOPSIS
        等某个窗口出现。
    .EXAMPLE
        $w = Wait-Window -TitleLike '记事本' -TimeoutMs 8000
        if (-not $w) { throw '记事本没打开' }
    #>
    param(
        [string]$TitleLike,
        [string]$ProcessName,
        [string]$ClassLike,
        [int]$TimeoutMs = 10000,
        [int]$IntervalMs = 250
    )

    # 这里不用 Wait-Until，因为它只返回真假、拿不到窗口对象本身。
    # 轮询逻辑就这么几行，直接写反而更清楚。
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $w = Find-Window -TitleLike $TitleLike -ProcessName $ProcessName -ClassLike $ClassLike
        if ($w) { return $w }
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $null
}

function Wait-WindowGone {
    <#
    .SYNOPSIS
        等某个窗口消失（例如等"加载中"弹窗关掉）。
    #>
    param(
        [string]$TitleLike,
        [string]$ProcessName,
        [int]$TimeoutMs = 10000,
        [int]$IntervalMs = 250
    )

    return Wait-Until -TimeoutMs $TimeoutMs -IntervalMs $IntervalMs -Description '窗口消失' -Condition {
        $w = Find-Window -TitleLike $TitleLike -ProcessName $ProcessName
        $null -eq $w
    }
}

function Wait-WindowForeground {
    <#
    .SYNOPSIS
        等某个窗口真的变成前台（用于确认抢前台成功）。
    .NOTES
        SetForegroundWindow 会假成功，所以切完最好等这个函数确认。
    #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle,
        [int]$TimeoutMs = 3000,
        [int]$IntervalMs = 100
    )

    return Wait-Until -TimeoutMs $TimeoutMs -IntervalMs $IntervalMs -Description '窗口成为前台' -Condition {
        [GuiAutoNative]::GetForegroundWindow() -eq $Handle
    }
}

function Wait-Color {
    <#
    .SYNOPSIS
        等屏幕上某个颜色出现（例如等按钮从灰变蓝）。
    .PARAMETER Color
        #RRGGBB
    .PARAMETER Region
        @{X=;Y=;Width=;Height=} 限定的屏幕区域。给区域能快很多。
    .EXAMPLE
        Wait-Color -Color '#2563EB' -Region @{X=400;Y=300;Width=800;Height=400} -TimeoutMs 15000
    #>
    param(
        [Parameter(Mandatory)][string]$Color,
        [hashtable]$Region,
        [int]$Tolerance = 10,
        [int]$TimeoutMs = 10000,
        [int]$IntervalMs = 250
    )

    return Wait-Until -TimeoutMs $TimeoutMs -IntervalMs $IntervalMs -Description "颜色出现 $Color" -Condition {
        if ($Region) {
            $bmp = Get-ScreenBitmap -X $Region.X -Y $Region.Y -Width $Region.Width -Height $Region.Height
        }
        else {
            $bmp = Get-ScreenBitmap
        }
        try {
            $hit = Find-ColorBounds -Bitmap $bmp -Color $Color -Tolerance $Tolerance -MinPixels 10
            return ($null -ne $hit)
        }
        finally {
            $bmp.Dispose()
        }
    }
}

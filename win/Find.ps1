#Requires -Version 5.1
<#
    Find.ps1  ——  原语 4：找准地方

    截图拿到的是几百万个像素。你要在这些像素里找到"那个按钮在哪"。

    这里给两种找法：

      1. 找色（Find-ColorBounds）
         你知道按钮是某个蓝色，那就扫出这个颜色的包围盒。
         快、简单，但只适合颜色独特的目标。

      2. 找图（Find-Image）
         先截一张按钮的小图当模板，然后在整屏里找它。
         更稳（颜色变了也能中），但慢，而且缩放/DPI 一变就失效。

    ── 关于性能 ──
      Bitmap.GetPixel 是 .NET 方法，每调一次都要跨界一次。
      一张 1920x1080 的图有 200 万像素，用它扫会慢到以分钟计。

      正确的做法是 LockBits：
        一次性把像素内存"锁"住，复制成一个 byte[]，然后纯内存循环。
      速度能差两个数量级。

      这个文件里的所有扫描都走 LockBits。
#>

. "$PSScriptRoot\Native.ps1"

Add-Type -AssemblyName System.Drawing

# ─────────────────────────────────────────────────────────────
# 内部工具：把位图变成可以直接扫的 byte[]
# ─────────────────────────────────────────────────────────────
function Get-BitmapPixels {
    <#
    .SYNOPSIS
        把 Bitmap 转成 32 位 ARGB 的原始字节数组，方便高速扫描。
    .DESCRIPTION
        返回的对象里：
          Bytes  —— 每像素 4 字节，顺序是 B, G, R, A
          Stride —— 每一行占多少字节（可能大于 Width*4，因为内存对齐）
        取 (x, y) 的偏移 = y * Stride + x * 4
    .NOTES
        这是内部函数，但理解它才能自己改后面的算法。
    #>
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    # 先确保是 32bppArgb，否则 LockBits 的格式转换可能失败
    $src = $Bitmap
    $disposeSrc = $false
    if ($Bitmap.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) {
        $src = New-Object System.Drawing.Bitmap(
            $Bitmap.Width, $Bitmap.Height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($src)
        $g.DrawImage($Bitmap, 0, 0, $Bitmap.Width, $Bitmap.Height)
        $g.Dispose()
        $disposeSrc = $true
    }

    $w = $src.Width
    $h = $src.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $src.LockBits($rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

    try {
        $stride = $data.Stride
        $bytes = New-Object byte[] ($stride * $h)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    }
    finally {
        $src.UnlockBits($data)
        if ($disposeSrc) { $src.Dispose() }
    }

    return [pscustomobject]@{
        Bytes  = $bytes
        Stride = $stride
        Width  = $w
        Height = $h
    }
}

function ConvertFrom-HexColor {
    <#
    .SYNOPSIS
        把 #RRGGBB / #AARRGGBB 转成 R/G/B 三个数。
    .EXAMPLE
        ConvertFrom-HexColor -Hex '#2563EB'
    #>
    param([Parameter(Mandatory)][string]$Hex)

    $h = $Hex.TrimStart('#')
    if ($h.Length -eq 8) { $h = $h.Substring(2) }   # 去掉 alpha
    if ($h.Length -ne 6) { throw "颜色格式不对：$Hex（要 #RRGGBB）" }

    return [pscustomobject]@{
        R = [Convert]::ToInt32($h.Substring(0, 2), 16)
        G = [Convert]::ToInt32($h.Substring(2, 2), 16)
        B = [Convert]::ToInt32($h.Substring(4, 2), 16)
        Hex = "#$($h.ToUpper())"
    }
}

# ─────────────────────────────────────────────────────────────
# 找色：包围盒（最常用）
# ─────────────────────────────────────────────────────────────
function Find-ColorBounds {
    <#
    .SYNOPSIS
        在一张图里找出某个颜色的"包围盒"和中心点。
    .DESCRIPTION
        这就是"定位一个按钮"最简单粗暴的办法：
          - 按钮是独特的蓝色
          - 扫出所有蓝色像素的 min/max 坐标
          - 包围盒中心，就是可以点的地方

        注意：如果屏幕上还有别的同色元素，会被算进同一个包围盒。
        所以要么选一个独特的颜色，要么先用 -SearchRect 限定范围。
    .PARAMETER Bitmap
        要搜的图（通常是 Get-ScreenBitmap 或 Get-WindowBitmap 的结果）。
    .PARAMETER Color
        #RRGGBB。
    .PARAMETER Tolerance
        每个通道允许的误差（0-255）。截图有压缩/抗锯齿时调大一点。
    .PARAMETER SearchRect
        只在图内某块区域找，格式 @{X=;Y=;Width=;Height=}。
    .PARAMETER MinPixels
        少于这么多像素就当没找到（过滤噪点），默认 20。
    .OUTPUTS
        找到返回对象（Left/Top/Right/Bottom/Width/Height/CenterX/CenterY/PixelCount），
        没找到返回 $null。
    .EXAMPLE
        $bmp   = Get-ScreenBitmap
        $hit   = Find-ColorBounds -Bitmap $bmp -Color '#2563EB' -Tolerance 12
        if ($hit) { Invoke-Click -X $hit.CenterX -Y $hit.CenterY }
        $bmp.Dispose()
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)][string]$Color,
        [int]$Tolerance = 8,
        [hashtable]$SearchRect,
        [int]$MinPixels = 20
    )

    $target = ConvertFrom-HexColor -Hex $Color
    $img = Get-BitmapPixels -Bitmap $Bitmap
    $bytes = $img.Bytes
    $stride = $img.Stride

    # 搜索范围
    if ($SearchRect) {
        $x0 = [Math]::Max(0, $SearchRect.X)
        $y0 = [Math]::Max(0, $SearchRect.Y)
        $x1 = [Math]::Min($img.Width  - 1, $SearchRect.X + $SearchRect.Width  - 1)
        $y1 = [Math]::Min($img.Height - 1, $SearchRect.Y + $SearchRect.Height - 1)
    }
    else {
        $x0 = 0; $y0 = 0
        $x1 = $img.Width - 1; $y1 = $img.Height - 1
    }

    $minX = [int]::MaxValue; $maxX = -1
    $minY = [int]::MaxValue; $maxY = -1
    $count = 0

    $tr = $target.R; $tg = $target.G; $tb = $target.B
    $tol = $Tolerance

    for ($y = $y0; $y -le $y1; $y++) {
        $rowBase = $y * $stride
        for ($x = $x0; $x -le $x1; $x++) {
            $i = $rowBase + $x * 4
            # 内存里的顺序是 B, G, R, A
            $b = $bytes[$i]
            $g = $bytes[$i + 1]
            $r = $bytes[$i + 2]

            if ([Math]::Abs($r - $tr) -le $tol -and
                [Math]::Abs($g - $tg) -le $tol -and
                [Math]::Abs($b - $tb) -le $tol) {

                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
                $count++
            }
        }
    }

    if ($count -lt $MinPixels) { return $null }

    return [pscustomobject]@{
        Left       = $minX
        Top        = $minY
        Right      = $maxX
        Bottom     = $maxY
        Width      = $maxX - $minX + 1
        Height     = $maxY - $minY + 1
        CenterX    = [int](($minX + $maxX) / 2)
        CenterY    = [int](($minY + $maxY) / 2)
        PixelCount = $count
        Color      = $target.Hex
    }
}

function Find-ColorPoint {
    <#
    .SYNOPSIS
        找出第一个匹配的像素点（左上优先）。
    .NOTES
        只是想确认"这个颜色在不在"的时候用它，比 Find-ColorBounds 快一点点。
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)][string]$Color,
        [int]$Tolerance = 8
    )

    $target = ConvertFrom-HexColor -Hex $Color
    $img = Get-BitmapPixels -Bitmap $Bitmap
    $bytes = $img.Bytes
    $stride = $img.Stride

    for ($y = 0; $y -lt $img.Height; $y++) {
        $rowBase = $y * $stride
        for ($x = 0; $x -lt $img.Width; $x++) {
            $i = $rowBase + $x * 4
            if ([Math]::Abs($bytes[$i + 2] - $target.R) -le $Tolerance -and
                [Math]::Abs($bytes[$i + 1] - $target.G) -le $Tolerance -and
                [Math]::Abs($bytes[$i]     - $target.B) -le $Tolerance) {
                return [pscustomobject]@{ X = $x; Y = $y }
            }
        }
    }
    return $null
}

# ─────────────────────────────────────────────────────────────
# 找图：朴素模板匹配
# ─────────────────────────────────────────────────────────────
function Find-Image {
    <#
    .SYNOPSIS
        在整屏里找一张小图（模板），返回它在屏幕上的位置。
    .DESCRIPTION
        算法就是最笨的那种：把模板在大图上滑一圈，逐像素比对，
        差异小于阈值就认为匹配。

        为什么给最笨的？
          因为最好懂、最好改。想优化就照注释里说的加步长或降采样。

        ⚠️ 三个已知的失效场景：
          1. DPI 缩放变了（模板是在 100% 下截的，屏幕上却是 150%）
          2. 窗口主题/深色模式切换
          3. 目标被部分遮挡
    .PARAMETER Source
        大图（通常是屏幕截图）。
    .PARAMETER Template
        小图（预先截好的按钮/图标）。
    .PARAMETER Tolerance
        每个通道允许的误差。截图有缩放时建议 20-40。
    .PARAMETER Step
        搜索步长。1 = 逐像素（最准最慢）；2-4 = 跳着搜（快，可能漏掉 1-2 像素的偏差）。
    .OUTPUTS
        找到返回 @{X=;Y=;Score=}，X/Y 是屏幕/大图坐标，Score 是平均误差（越小越像）。
    .EXAMPLE
        $screen   = Get-ScreenBitmap
        $template = Open-ImageFile -Path '.\assets\login-button.png'
        $hit      = Find-Image -Source $screen -Template $template -Tolerance 30 -Step 2
        if ($hit) { "找到，误差 $($hit.Score)" }
        $screen.Dispose()
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Source,
        [Parameter(Mandatory)][System.Drawing.Image]$Template,
        [int]$Tolerance = 24,
        [int]$Step = 1
    )

    $big  = Get-BitmapPixels -Bitmap $Source
    $tmpl = Get-BitmapPixels -Bitmap ([System.Drawing.Bitmap]$Template)

    $tw = $tmpl.Width; $th = $tmpl.Height
    $maxX = $big.Width  - $tw
    $maxY = $big.Height - $th
    if ($maxX -lt 0 -or $maxY -lt 0) { return $null }

    for ($oy = 0; $oy -le $maxY; $oy += $Step) {
        for ($ox = 0; $ox -le $maxX; $ox += $Step) {

            $mismatch = 0
            $failed = $false

            for ($ty = 0; $ty -lt $th -and -not $failed; $ty++) {
                $bigRow  = ($oy + $ty) * $big.Stride
                $tmplRow = $ty * $tmpl.Stride

                for ($tx = 0; $tx -lt $tw; $tx++) {
                    $bi = $bigRow  + ($ox + $tx) * 4
                    $ti = $tmplRow + $tx * 4

                    $db = [Math]::Abs($big.Bytes[$bi]     - $tmpl.Bytes[$ti])
                    $dg = [Math]::Abs($big.Bytes[$bi + 1] - $tmpl.Bytes[$ti + 1])
                    $dr = [Math]::Abs($big.Bytes[$bi + 2] - $tmpl.Bytes[$ti + 2])

                    if ($db -gt $Tolerance -or $dg -gt $Tolerance -or $dr -gt $Tolerance) {
                        $failed = $true
                        break
                    }
                    $mismatch += $db + $dg + $dr
                }
            }

            if (-not $failed) {
                $pixels = $tw * $th
                return [pscustomobject]@{
                    X     = $ox
                    Y     = $oy
                    Score = [Math]::Round($mismatch / ($pixels * 3), 2)
                    Width = $tw
                    Height = $th
                }
            }
        }
    }

    return $null
}

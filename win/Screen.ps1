#Requires -Version 5.1
<#
    Screen.ps1  ——  原语 1：看

    GUI 自动化的第一步永远是"看见"。看不见就没法找，没找就没法点。

    这里给两套实现：

      A. 简单版  Get-ScreenBitmap
         用 System.Drawing 自带的 CopyFromScreen，三行搞定。
         原理是 Windows 帮你做了一次 BitBlt，够用，好懂。

      B. 原生版  Get-ScreenBitmapNative
         自己 GetDC -> CreateCompatibleDC -> BitBlt。
         多出来的价值是：你能控制抓哪块、什么时候抓、抓完自己还资源。
         这也是所有截图工具（包括 OBS、ShareX）底下那一层。

    还有一个特殊货：Get-WindowBitmap
      用 PrintWindow，能把"被别的窗口挡住"的窗口内容抓出来，
      甚至可以把窗口抓成它完全在前台的样子。
      缺点是有些程序（尤其是硬件加速渲染的）抓出来是黑的。
#>

# 所有函数都依赖 Native.ps1 里的 Win32 声明
. "$PSScriptRoot\Native.ps1"

Add-Type -AssemblyName System.Drawing

# ─────────────────────────────────────────────────────────────
# 桌面范围（多显示器时是"虚拟桌面"的总范围）
# ─────────────────────────────────────────────────────────────
function Get-ScreenRect {
    <#
    .SYNOPSIS
        返回整个虚拟桌面的边界。
    .EXAMPLE
        Get-ScreenRect
        # Left Top Right Bottom Width Height
    #>
    Add-Type -AssemblyName System.Windows.Forms
    $v = [System.Windows.Forms.SystemInformation]::VirtualScreen
    [pscustomobject]@{
        Left   = $v.Left
        Top    = $v.Top
        Width  = $v.Width
        Height = $v.Height
        Right  = $v.Left + $v.Width
        Bottom = $v.Top + $v.Height
    }
}

# ─────────────────────────────────────────────────────────────
# A. 截屏（简单版）
# ─────────────────────────────────────────────────────────────
function Get-ScreenBitmap {
    <#
    .SYNOPSIS
        截取屏幕（或屏幕上的一块），返回 System.Drawing.Bitmap。
    .PARAMETER X / Y / Width / Height
        不给就是整个虚拟桌面。
    .NOTES
        调用方负责 Dispose 返回的 Bitmap。
    #>
    param(
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 0,
        [int]$Height = 0
    )

    if ($Width -le 0 -or $Height -le 0) {
        $rect = Get-ScreenRect
        $X = $rect.Left; $Y = $rect.Top
        $Width = $rect.Width; $Height = $rect.Height
    }

    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($X, $Y, 0, 0, $bmp.Size)
    }
    finally {
        $g.Dispose()
    }
    return $bmp
}

# ─────────────────────────────────────────────────────────────
# B. 截屏（原生 GDI 版）
# ─────────────────────────────────────────────────────────────
function Get-ScreenBitmapNative {
    <#
    .SYNOPSIS
        直接调 GDI 的 BitBlt 截屏，不经过 Graphics.CopyFromScreen。
    .DESCRIPTION
        四步，一步都不能少：
          1. GetDC(NULL)                     拿到整个屏幕的设备上下文
          2. CreateCompatibleDC + Bitmap     在内存里准备一张同样格式的画布
          3. SelectObject + BitBlt           把屏幕像素拷到内存画布
          4. 转成 Bitmap，然后 DeleteObject / DeleteDC / ReleaseDC

        第 4 步最容易被忘。忘了就泄漏 —— 每截一次泄漏一张图的内存，
        跑几百次之后整个进程会变慢甚至崩。
    #>
    param(
        [int]$X = 0,
        [int]$Y = 0,
        [int]$Width = 0,
        [int]$Height = 0
    )

    if ($Width -le 0 -or $Height -le 0) {
        $rect = Get-ScreenRect
        $X = $rect.Left; $Y = $rect.Top
        $Width = $rect.Width; $Height = $rect.Height
    }

    $screenDc = [GuiAutoNative]::GetDC([IntPtr]::Zero)
    $memDc    = [GuiAutoNative]::CreateCompatibleDC($screenDc)
    $hBitmap  = [GuiAutoNative]::CreateCompatibleBitmap($screenDc, $Width, $Height)
    $old      = [GuiAutoNative]::SelectObject($memDc, $hBitmap)

    try {
        [void][GuiAutoNative]::BitBlt(
            $memDc, 0, 0, $Width, $Height,
            $screenDc, $X, $Y,
            [GuiAutoNative]::SRCCOPY
        )
        # Image.FromHbitmap 会复制一份像素，所以后面可以放心删句柄
        $bmp = [System.Drawing.Image]::FromHbitmap($hBitmap)
    }
    finally {
        [void][GuiAutoNative]::SelectObject($memDc, $old)
        [void][GuiAutoNative]::DeleteObject($hBitmap)
        [void][GuiAutoNative]::DeleteDC($memDc)
        [void][GuiAutoNative]::ReleaseDC([IntPtr]::Zero, $screenDc)
    }
    return $bmp
}

# ─────────────────────────────────────────────────────────────
# 抓指定窗口（哪怕被挡住）
# ─────────────────────────────────────────────────────────────
function Get-WindowBitmap {
    <#
    .SYNOPSIS
        抓一个窗口的内容，即使它被别的窗口盖住。
    .PARAMETER Handle
        窗口句柄（IntPtr）。用 Window.ps1 里的 Find-Window 拿到。
    .EXAMPLE
        $w = Find-Window -TitleLike '记事本'
        $bmp = Get-WindowBitmap -Handle $w.Handle
        Save-Bitmap -Bitmap $bmp -Path D:\tmp\notepad.png
    .NOTES
        硬件加速渲染的窗口（游戏、部分 Electron 应用）可能抓出全黑。
        这时候只能退回到"把窗口搬到前台再截屏幕"。
    #>
    param(
        [Parameter(Mandatory)][IntPtr]$Handle
    )

    $rect = [GuiAutoNative]::WindowRect($Handle)
    $w = $rect.Width
    $h = $rect.Height
    if ($w -le 0 -or $h -le 0) {
        throw "窗口尺寸无效（$w x $h），可能已经关闭或最小化。"
    }

    $screenDc = [GuiAutoNative]::GetDC([IntPtr]::Zero)
    $memDc    = [GuiAutoNative]::CreateCompatibleDC($screenDc)
    $hBitmap  = [GuiAutoNative]::CreateCompatibleBitmap($screenDc, $w, $h)
    $old      = [GuiAutoNative]::SelectObject($memDc, $hBitmap)

    try {
        $ok = [GuiAutoNative]::PrintWindow(
            $Handle, $memDc, [GuiAutoNative]::PW_RENDERFULLCONTENT)

        if (-not $ok) {
            # 有些老程序不认 PW_RENDERFULLCONTENT，退回 0 再试一次
            $ok = [GuiAutoNative]::PrintWindow($Handle, $memDc, 0)
        }
        if (-not $ok) {
            throw "PrintWindow 失败：这个窗口不允许被抓取。"
        }
        $bmp = [System.Drawing.Image]::FromHbitmap($hBitmap)
    }
    finally {
        [void][GuiAutoNative]::SelectObject($memDc, $old)
        [void][GuiAutoNative]::DeleteObject($hBitmap)
        [void][GuiAutoNative]::DeleteDC($memDc)
        [void][GuiAutoNative]::ReleaseDC([IntPtr]::Zero, $screenDc)
    }
    return $bmp
}

# ─────────────────────────────────────────────────────────────
# 存图 / 读图
# ─────────────────────────────────────────────────────────────
function Save-Bitmap {
    <#
    .SYNOPSIS
        把 Bitmap 存成文件。扩展名决定格式（.png 最好，无损）。
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $fmt = switch ($ext) {
        '.png'  { [System.Drawing.Imaging.ImageFormat]::Png }
        '.jpg'  { [System.Drawing.Imaging.ImageFormat]::Jpeg }
        '.bmp'  { [System.Drawing.Imaging.ImageFormat]::Bmp }
        default { [System.Drawing.Imaging.ImageFormat]::Png }
    }
    $Bitmap.Save($Path, $fmt)
    return (Get-Item $Path).FullName
}

function Open-ImageFile {
    <#
    .SYNOPSIS
        读一张图进来（做模板匹配时要用）。
    .NOTES
        文件会被锁住直到 Bitmap 被 Dispose，所以这里先读进内存再放开文件。
    #>
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path))
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    return [System.Drawing.Image]::FromStream($ms)
}

# ─────────────────────────────────────────────────────────────
# 取一个点的颜色
# ─────────────────────────────────────────────────────────────
function Get-PixelColor {
    <#
    .SYNOPSIS
        读屏幕上某一点的颜色，返回 #RRGGBB。
    .PARAMETER X / Y
        屏幕绝对坐标。
    .EXAMPLE
        Get-PixelColor -X 100 -Y 200
    .NOTES
        每次都新建一个 DC、读完就还。
        要连续读很多点别这么干 —— 用 Find.ps1 里的批量读取。
    #>
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )

    $dc = [GuiAutoNative]::GetDC([IntPtr]::Zero)
    try {
        $color = [GuiAutoNative]::GetPixel($dc, $X, $Y)
    }
    finally {
        [void][GuiAutoNative]::ReleaseDC([IntPtr]::Zero, $dc)
    }

    if ($color -eq 0xFFFFFFFF) { return $null }   # CLR_INVALID

    $r = [int]($color -band 0xFF)
    $g = [int](($color -shr 8) -band 0xFF)
    $b = [int](($color -shr 16) -band 0xFF)
    return ('#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
}

#Requires -Version 5.1
<#
    示例 1：截一张屏，存下来，再读一个像素的颜色

    跑法：
        powershell -ExecutionPolicy Bypass -File .\examples\01-screenshot.ps1

    你会得到：
        - 一张全屏 PNG（存在临时目录）
        - 屏幕分辨率
        - 鼠标当前所在位置的颜色
#>

. "$PSScriptRoot\..\win\Screen.ps1"
. "$PSScriptRoot\..\win\Input.ps1"

$rect = Get-ScreenRect
Write-Host "屏幕范围: $($rect.Left),$($rect.Top) - $($rect.Right),$($rect.Bottom)  ($($rect.Width)x$($rect.Height))"

# ── 截一张全屏 ──
$path = Join-Path $env:TEMP 'mouse-and-eyes-shot.png'
$bmp = Get-ScreenBitmap
try {
    Save-Bitmap -Bitmap $bmp -Path $path | Out-Null
    Write-Host "截图已保存: $path"
}
finally {
    # 一定要 Dispose，否则 GDI 句柄会一直涨
    $bmp.Dispose()
}

# ── 读鼠标当前位置的颜色 ──
$cursor = Get-CursorPosition
$color = Get-PixelColor -X $cursor.X -Y $cursor.Y
Write-Host "鼠标在 $($cursor.X),$($cursor.Y)，那里的颜色是 $color"

# ── 顺便演示原生 GDI 截屏（结果和上面一样，只是路径不同）──
$native = Get-ScreenBitmapNative -Width 200 -Height 100
try {
    $nativePath = Join-Path $env:TEMP 'mouse-and-eyes-native.png'
    Save-Bitmap -Bitmap $native -Path $nativePath | Out-Null
    Write-Host "原生 BitBlt 截的小图: $nativePath"
}
finally {
    $native.Dispose()
}

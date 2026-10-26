#Requires -Version 5.1
<#
    示例 2：在屏幕上找到一个颜色，算出它的中心，然后（可选）点它

    这是最经典的「无依赖 GUI 自动化」招式，也是很多 RPA 工具底下的东西：
        截图 -> 找特征色 -> 包围盒 -> 取中心 -> 点

    默认只报告不点击（dry-run），加 -Execute 才会真的点。
    这是故意的 —— 自动点击很容易在错误的窗口上闯祸。

    跑法：
        # 只看，不动手
        powershell -ExecutionPolicy Bypass -File .\examples\02-click-color.ps1

        # 真的点击（自己先把 -Color 换成目标按钮的颜色）
        powershell -ExecutionPolicy Bypass -File .\examples\02-click-color.ps1 -Color '#2563EB' -Execute
#>

param(
    [string]$Color = '#2563EB',
    [int]$Tolerance = 12,
    [switch]$Execute
)

. "$PSScriptRoot\..\win\Screen.ps1"
. "$PSScriptRoot\..\win\Find.ps1"
. "$PSScriptRoot\..\win\Input.ps1"

Write-Host "正在找颜色 $Color（容差 $Tolerance）..."

$bmp = Get-ScreenBitmap
try {
    $hit = Find-ColorBounds -Bitmap $bmp -Color $Color -Tolerance $Tolerance -MinPixels 20
}
finally {
    $bmp.Dispose()
}

if (-not $hit) {
    Write-Host "没找到。可能这个颜色不在屏幕上，或者容差太小。"
    Write-Host "提示：可以先用 01-screenshot.ps1 截个图，用画图工具吸一下目标按钮的颜色。"
    exit 1
}

Write-Host ""
Write-Host "找到了："
Write-Host "  包围盒 : $($hit.Left),$($hit.Top) - $($hit.Right),$($hit.Bottom)"
Write-Host "  尺寸   : $($hit.Width) x $($hit.Height)"
Write-Host "  中心   : $($hit.CenterX), $($hit.CenterY)"
Write-Host "  像素数 : $($hit.PixelCount)"
Write-Host ""

if ($Execute) {
    Write-Host "3 秒后点击 $($hit.CenterX),$($hit.CenterY) ...（把鼠标挪开或者关掉窗口可以取消）"
    Start-Sleep -Seconds 3
    Invoke-Click -X $hit.CenterX -Y $hit.CenterY
    Write-Host "点完了。"
}
else {
    Write-Host "（dry-run，没有点击。加 -Execute 才会真的点）"
}

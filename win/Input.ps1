#Requires -Version 5.1
<#
    Input.ps1  ——  原语 3：动

    鼠标和键盘在 Windows 上有两套 API：

      老的一套：SetCursorPos + mouse_event + keybd_event
        能用，但限制多。最大的坑是 keybd_event 的"扫描码"只有 8 位，
        发不了中文字符（Unicode 码点超过 255）。

      新的一套：SendInput
        把所有输入打包成结构体数组一次性提交，更准确，也能正确发 Unicode。
        代价是要写一堆结构体定义。

    这个文件把两套都给了：
      Invoke-Click / Invoke-MouseMove    → 老 API，够简单
      Send-UnicodeText                   → 新 API，中文靠它

    一个通用原则：**先移光标，再按键**。
      因为 mouse_event 的 dx/dy 是"相对位移"，很多人以为可以传绝对坐标，
      结果点到了不确定的地方。先用 SetCursorPos 把光标放到确定的位置，
      再发 down/up，就绝对不会错。
#>

. "$PSScriptRoot\Native.ps1"

# ─────────────────────────────────────────────────────────────
# SendInput：正确发送 Unicode 字符（中文必需）
# ─────────────────────────────────────────────────────────────
if (-not ("GuiAutoInput" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class GuiAutoInput
{
    public const uint INPUT_MOUSE    = 0;
    public const uint INPUT_KEYBOARD = 1;

    public const uint KEYEVENTF_KEYUP       = 0x0002;
    public const uint KEYEVENTF_UNICODE     = 0x0004;
    public const uint KEYEVENTF_SCANCODE    = 0x0008;

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int    dx;
        public int    dy;
        public uint   mouseData;
        public uint   dwFlags;
        public uint   time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint   dwFlags;
        public uint   time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT
    {
        public uint   uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT    mi;
        [FieldOffset(0)] public KEYBDINPUT    ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT
    {
        public uint       type;
        public InputUnion u;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    // 把一串字符变成 SendInput 数组，一次性发出去。
    // 每个字符要两条：按下 + 抬起。
    public static int TypeText(string text)
    {
        if (string.IsNullOrEmpty(text)) return 0;

        INPUT[] inputs = new INPUT[text.Length * 2];

        for (int i = 0; i < text.Length; i++)
        {
            char c = text[i];

            INPUT down = new INPUT();
            down.type = INPUT_KEYBOARD;
            down.u.ki.wVk   = 0;
            down.u.ki.wScan = c;
            down.u.ki.dwFlags = KEYEVENTF_UNICODE;

            // 回车要单独处理：\n 发成真正的 VK_RETURN
            if (c == '\n')
            {
                down.u.ki.wVk = 0x0D;                 // VK_RETURN
                down.u.ki.wScan = 0;
                down.u.ki.dwFlags = 0;
            }

            INPUT up = down;
            up.u.ki.dwFlags = down.u.ki.dwFlags | KEYEVENTF_KEYUP;

            inputs[i * 2]     = down;
            inputs[i * 2 + 1] = up;
        }

        int size = Marshal.SizeOf(typeof(INPUT));
        uint sent = SendInput((uint)inputs.Length, inputs, size);
        return (int)sent;
    }
}
'@ -ErrorAction Stop
}

# ─────────────────────────────────────────────────────────────
# 鼠标
# ─────────────────────────────────────────────────────────────
function Invoke-MouseMove {
    <#
    .SYNOPSIS
        把鼠标移到屏幕绝对坐标。
    #>
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [int]$SettleMs = 60
    )
    $ok = [GuiAutoNative]::SetCursorPos($X, $Y)
    if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
    return $ok
}

function Invoke-Click {
    <#
    .SYNOPSIS
        在屏幕绝对坐标点一下（或多个）。
    .PARAMETER Button
        Left / Right / Middle
    .PARAMETER Count
        点几次。2 = 双击。两次之间会留 120ms，太快系统会当成两次单击。
    .EXAMPLE
        Invoke-Click -X 800 -Y 450
        Invoke-Click -X 800 -Y 450 -Count 2
    .NOTES
        顺序永远是：移过去 -> 等一下 -> 按下 -> 抬起。
        那个"等一下"很重要，窗口可能需要几十毫秒才反应过来。
    #>
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [ValidateSet('Left', 'Right', 'Middle')][string]$Button = 'Left',
        [int]$Count = 1,
        [int]$HoldMs = 40,
        [int]$GapMs = 120
    )

    switch ($Button) {
        'Left'   { $down = [GuiAutoNative]::MOUSEEVENTF_LEFTDOWN;   $up = [GuiAutoNative]::MOUSEEVENTF_LEFTUP }
        'Right'  { $down = [GuiAutoNative]::MOUSEEVENTF_RIGHTDOWN;  $up = [GuiAutoNative]::MOUSEEVENTF_RIGHTUP }
        'Middle' { $down = [GuiAutoNative]::MOUSEEVENTF_MIDDLEDOWN; $up = [GuiAutoNative]::MOUSEEVENTF_MIDDLEUP }
    }

    [void][GuiAutoNative]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 80

    for ($i = 0; $i -lt $Count; $i++) {
        [GuiAutoNative]::mouse_event($down, 0, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds $HoldMs
        [GuiAutoNative]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
        if ($i -lt $Count - 1) { Start-Sleep -Milliseconds $GapMs }
    }
}

function Invoke-Scroll {
    <#
    .SYNOPSIS
        在当前位置滚轮。
    .PARAMETER Delta
        正数向上，负数向下。一格 = 120。
    .EXAMPLE
        Invoke-Scroll -Delta -360      # 向下滚三格
    #>
    param([Parameter(Mandatory)][int]$Delta)
    [GuiAutoNative]::mouse_event(
        [GuiAutoNative]::MOUSEEVENTF_WHEEL, 0, 0, [uint32]$Delta, [IntPtr]::Zero)
}

function Get-CursorPosition {
    <#
    .SYNOPSIS
        当前鼠标在屏幕上的坐标。
    #>
    $p = New-Object GuiAutoNative+POINT
    [void][GuiAutoNative]::GetCursorPos([ref]$p)
    return [pscustomobject]@{ X = $p.X; Y = $p.Y }
}

# ─────────────────────────────────────────────────────────────
# 键盘
# ─────────────────────────────────────────────────────────────
function Send-UnicodeText {
    <#
    .SYNOPSIS
        把一段文字"打"进当前焦点窗口，支持中文。
    .PARAMETER Text
        要输入的文字。\n 会变成回车。
    .EXAMPLE
        Send-UnicodeText -Text '你好，世界'
    .NOTES
        先用 Set-WindowForeground 把目标窗口切到前台、并点一下输入框，
        再调这个函数。否则字会打到不知道哪去。
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$PerCharDelayMs = 0
    )

    if ($PerCharDelayMs -le 0) {
        return [GuiAutoInput]::TypeText($Text)
    }

    foreach ($ch in $Text.ToCharArray()) {
        [void][GuiAutoInput]::TypeText([string]$ch)
        Start-Sleep -Milliseconds $PerCharDelayMs
    }
}

function Send-Key {
    <#
    .SYNOPSIS
        按一个虚拟键，比如 {ENTER}、{TAB}、{ESC}、{F5}。
    .PARAMETER Name
        键名，用 System.Windows.Forms.SendKeys 的写法。
    .EXAMPLE
        Send-Key -Name '{ENTER}'
        Send-Key -Name '^a'          # Ctrl+A
    .NOTES
        这个走 .NET 的 SendKeys，只适合 ASCII 组合键，不要用它发中文。
    #>
    param([Parameter(Mandatory)][string]$Name)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait($Name)
}

function Send-KeyCode {
    <#
    .SYNOPSIS
        按一个虚拟键码（VK_*），可以按住组合键。
    .PARAMETER Vk
        虚拟键码。常用：0x0D=回车 0x09=Tab 0x1B=Esc 0x20=空格。
    .EXAMPLE
        Send-KeyCode -Vk 0x0D                 # 回车
        Send-KeyCode -Vk 0x41 -Modifier 0x11  # Ctrl+A
    #>
    param(
        [Parameter(Mandatory)][int]$Vk,
        [int]$Modifier = 0,
        [int]$HoldMs = 30
    )

    if ($Modifier -ne 0) {
        [GuiAutoNative]::keybd_event([byte]$Modifier, 0, 0, [IntPtr]::Zero)
        Start-Sleep -Milliseconds 20
    }

    [GuiAutoNative]::keybd_event([byte]$Vk, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds $HoldMs
    [GuiAutoNative]::keybd_event([byte]$Vk, 0, [GuiAutoNative]::KEYEVENTF_KEYUP, [IntPtr]::Zero)

    if ($Modifier -ne 0) {
        Start-Sleep -Milliseconds 20
        [GuiAutoNative]::keybd_event([byte]$Modifier, 0, [GuiAutoNative]::KEYEVENTF_KEYUP, [IntPtr]::Zero)
    }
}

# ─────────────────────────────────────────────────────────────
# 剪贴板（发长文本比逐字打快得多）
# ─────────────────────────────────────────────────────────────
function Set-ClipboardText {
    <#
    .SYNOPSIS
        把文字放进剪贴板，配合 Ctrl+V 粘贴。
    .NOTES
        要发几百字的话，这比 Send-UnicodeText 快几十倍。
        代价是会覆盖用户剪贴板里的内容。
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    Set-Clipboard -Value $Text
}

function Invoke-Paste {
    <#
    .SYNOPSIS
        在当前焦点处按 Ctrl+V。
    #>
    Send-KeyCode -Vk 0x56 -Modifier 0x11
}

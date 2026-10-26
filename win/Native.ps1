#Requires -Version 5.1
<#
    Native.ps1  ——  这个项目用到的全部 Win32 声明，一共就这些

    为什么要单独一个文件？
      因为 P/Invoke 是整套代码里唯一"看起来像魔法"的部分。
      把它们抽到一个文件，剩下的 .ps1 就都是普通逻辑，谁都能读、能改。

    P/Invoke 到底是什么？
      PowerShell 跑在 .NET 上，而 .NET 默认不跟 Windows 的 C 接口说话。
      [DllImport("user32.dll")] 这句就是在说：
        "user32.dll 里有个叫 SetCursorPos 的函数，签名长这样，帮我接上。"
      接上之后，你就是在直接调操作系统的 API —— 没有框架、没有中间层。

    约定
      - 全用 Unicode(W) 版本，避免中文窗口标题乱码
      - 指针一律 IntPtr（64 位系统上就是 8 字节）
      - 句柄用完要还，GDI 对象用完要删，否则会泄漏（见 Screen.ps1）
#>

if (-not ("GuiAutoNative" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class GuiAutoNative
{
    // ─────────────────────────────────────────────────────────────
    // 结构体：Windows 的坐标和矩形
    // ─────────────────────────────────────────────────────────────

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public int Width  { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
        public override string ToString()
        {
            return string.Format("{0},{1} - {2},{3}  ({4}x{5})",
                Left, Top, Right, Bottom, Width, Height);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
        public override string ToString() { return string.Format("{0},{1}", X, Y); }
    }

    // ─────────────────────────────────────────────────────────────
    // 窗口：枚举、查属性、搬前台
    // ─────────────────────────────────────────────────────────────

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr hWnd, StringBuilder name, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    // SetWindowPos 的 hWndInsertAfter 特殊值
    public static readonly IntPtr HWND_TOPMOST   = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

    // SetWindowPos 的 flags
    public const uint SWP_NOSIZE   = 0x0001;
    public const uint SWP_NOMOVE   = 0x0002;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_SHOWWINDOW = 0x0040;

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter,
        int x, int y, int cx, int cy, uint flags);

    // AttachThreadInput 是"抢前台"的关键，理由见 Window.ps1
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);

    public const uint GW_OWNER = 4;

    // ─────────────────────────────────────────────────────────────
    // 鼠标与键盘
    // ─────────────────────────────────────────────────────────────

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    // mouse_event 的 flags
    public const uint MOUSEEVENTF_LEFTDOWN   = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP     = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN  = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP    = 0x0010;
    public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    public const uint MOUSEEVENTF_MIDDLEUP   = 0x0040;
    public const uint MOUSEEVENTF_WHEEL      = 0x0800;
    public const uint MOUSEEVENTF_HWHEEL     = 0x01000;

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extraInfo);

    // keybd_event 的 flags
    public const uint KEYEVENTF_KEYUP   = 0x0002;
    public const uint KEYEVENTF_UNICODE = 0x0004;

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extraInfo);

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint code, uint mapType);

    // ─────────────────────────────────────────────────────────────
    // 屏幕：GDI 截图与取色
    // ─────────────────────────────────────────────────────────────

    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    // PrintWindow 能抓"被别的窗口挡住"的窗口，第 3 个参数传 2 = PW_RENDERFULLCONTENT
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);

    public const uint PW_RENDERFULLCONTENT = 2;

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int width, int height);

    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);

    [DllImport("gdi32.dll")]
    public static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int width, int height,
        IntPtr hdcSrc, int xSrc, int ySrc, uint rop);

    public const uint SRCCOPY = 0x00CC0020;

    [DllImport("gdi32.dll")]
    public static extern bool DeleteObject(IntPtr obj);

    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    public static extern uint GetPixel(IntPtr hdc, int x, int y);

    // ─────────────────────────────────────────────────────────────
    // 小工具：把 RECT/字符串转换 做成静态方法，调用处就不写了
    // ─────────────────────────────────────────────────────────────

    public static string WindowTitle(IntPtr hWnd)
    {
        StringBuilder sb = new StringBuilder(512);
        GetWindowTextW(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string WindowClass(IntPtr hWnd)
    {
        StringBuilder sb = new StringBuilder(256);
        GetClassNameW(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static uint WindowProcessId(IntPtr hWnd)
    {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return pid;
    }

    public static RECT WindowRect(IntPtr hWnd)
    {
        RECT r;
        GetWindowRect(hWnd, out r);
        return r;
    }

    // ─────────────────────────────────────────────────────────
    // 窗口清单
    //
    // 为什么放在 C# 里而不是 PowerShell？
    //   因为 EnumWindows 的回调是个"委托"，会被系统在另一个线程里调用。
    //   PowerShell 的脚本块当委托用时，作用域是断的 ——
    //   在回调里往函数里的局部 List 里 Add，很可能什么都加不进去（还不报错）。
    //   放进 C# 就没有这个问题，顺带还更快。
    // ─────────────────────────────────────────────────────────

    public class WindowInfo
    {
        public IntPtr Handle;
        public string Title;
        public string ClassName;
        public uint   ProcessId;
        public int    Left;
        public int    Top;
        public int    Right;
        public int    Bottom;

        public int Width  { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
    }

    public static WindowInfo[] ListWindows(bool includeUntitled)
    {
        List<WindowInfo> found = new List<WindowInfo>();

        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            if (!IsWindowVisible(hWnd)) return true;

            string title = WindowTitle(hWnd);
            if (!includeUntitled && string.IsNullOrEmpty(title.Trim())) return true;

            RECT r;
            if (!GetWindowRect(hWnd, out r)) return true;
            if (r.Right - r.Left <= 0 || r.Bottom - r.Top <= 0) return true;

            WindowInfo info = new WindowInfo();
            info.Handle     = hWnd;
            info.Title      = title;
            info.ClassName  = WindowClass(hWnd);
            info.ProcessId  = WindowProcessId(hWnd);
            info.Left       = r.Left;
            info.Top        = r.Top;
            info.Right      = r.Right;
            info.Bottom     = r.Bottom;

            found.Add(info);
            return true;
        }, IntPtr.Zero);

        return found.ToArray();
    }
}
'@ -ErrorAction Stop
}

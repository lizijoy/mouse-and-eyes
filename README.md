# mouse-and-eyes

**用 Windows 最原始的 API，做 GUI 自动化的五个原语。**

零依赖 · 纯 PowerShell · 每个文件 100 行上下 · MIT

---

> 看见 → 找到 → 动 → 确认
>
> 所有 GUI 自动化框架，底下都是这四个动作加上几个 Win32 函数。
> 这个仓库把它们拆开，让你看见里面是什么。

## 这是什么

一套**可以完整读懂的** GUI 自动化实现。

没有 `pip install`，没有框架，没有配置文件。
只要有 Windows 和自带的 PowerShell，就能跑。

```powershell
. .\win\Screen.ps1
. .\win\Find.ps1
. .\win\Input.ps1

$bmp = Get-ScreenBitmap
$hit = Find-ColorBounds -Bitmap $bmp -Color '#2563EB'   # 找那个蓝按钮
Invoke-Click -X $hit.CenterX -Y $hit.CenterY            # 点它
$bmp.Dispose()
```

上面这段就是全部——截图、找色、算中心、点击。

## 这不是什么

- ❌ 不是生产框架。要稳定跑业务请用 [pywinauto](https://github.com/pywinauto/pywinauto) 或商业 RPA
- ❌ 不能操作 Chromium / Electron 界面的控件（它们的无障碍树是空的，只能坐标点击）
- ❌ 不处理 DPI 缩放的换算（100% 缩放下最准，其他比例见 [docs/limits.md](docs/limits.md)）

**它的定位是：教学 + 兜底。** 你搞不懂某个框架为什么不工作时，来这里看底下那层。

---

## 五个原语

| # | 原语 | 文件 | 底层是什么 |
|---|------|------|-----------|
| 1 | **看** | `win/Screen.ps1` | `GetDC` → `CreateCompatibleBitmap` → `BitBlt` |
| 2 | **找窗口** | `win/Window.ps1` | `EnumWindows` + `GetWindowRect` + `AttachThreadInput` |
| 3 | **在像素里找** | `win/Find.ps1` | `LockBits` 拿原始字节，纯内存扫描 |
| 4 | **动** | `win/Input.ps1` | `SetCursorPos` / `mouse_event` / `SendInput` |
| 5 | **等** | `win/Wait.ps1` | 轮询直到条件成立（不是猜时间） |

外加一个 `win/Native.ps1`，装着全部 P/Invoke 声明——想看这个仓库到底用了哪些
Windows 函数，只看这一个文件就够。

---

## 快速开始

```powershell
git clone <this-repo>
cd mouse-and-eyes

# 1) 截一张屏，顺便读鼠标位置的颜色（安全，不改任何状态）
powershell -ExecutionPolicy Bypass -File .\examples\01-screenshot.ps1

# 2) 在屏幕上找一个颜色并报告位置（dry-run，默认不点）
powershell -ExecutionPolicy Bypass -File .\examples\02-click-color.ps1

# 3) 真的点（自己把颜色换成目标按钮的）
powershell -ExecutionPolicy Bypass -File .\examples\02-click-color.ps1 -Color '#2563EB' -Execute

# 4) 抢前台 + 输入中文（会开一个记事本当靶子，不碰你的文件）
powershell -ExecutionPolicy Bypass -File .\examples\03-focus-and-type.ps1
```

> ⚠️ 例子 3 会抢前台、开记事本、打字、然后关掉。介意的话别跑。

---

## 目录

```
mouse-and-eyes/
├── win/
│   ├── Native.ps1      全部 Win32 P/Invoke 声明（唯一的"魔法"都在这里）
│   ├── Screen.ps1      截图、抓窗口、取色
│   ├── Window.ps1      枚举、查找、抢前台、置顶、坐标换算
│   ├── Find.ps1        找色包围盒、找图（朴素模板匹配）
│   ├── Input.ps1       鼠标、键盘、中文输入、剪贴板
│   └── Wait.ps1        轮询等待原语
├── examples/
│   ├── 01-screenshot.ps1
│   ├── 02-click-color.ps1
│   └── 03-focus-and-type.ps1
├── docs/
│   ├── why.md          为什么手搓、和现有框架的关系
│   └── limits.md       什么时候不该用（建议先读这个）
├── LICENSE
└── README.md
```

---

## 三个值得单独说的技术点

### 1. 抢前台为什么要 `AttachThreadInput`

Windows 不允许后台程序随便把窗口顶上来。`SetForegroundWindow` 会
"返回成功但什么也没发生"。

```powershell
# 把自己线程挂到前台线程的输入队列上
AttachThreadInput($myThread, $fgThread, $true)
# 这时候系统认为你是前台的"兄弟"，才允许你切窗口
SetForegroundWindow($handle)
# 用完立刻断开
AttachThreadInput($myThread, $fgThread, $false)
```

### 2. 中文必须走 `SendInput`

`keybd_event` 的扫描码参数只有 8 位，发不了 Unicode 码点超过 255 的字符。
中文得用 `SendInput` + `KEYEVENTF_UNICODE`，`wScan` 是 16 位的。

### 3. 扫描像素必须用 `LockBits`

`Bitmap.GetPixel` 每调一次都要跨一次 .NET 边界。
一张 1920×1080 的图有 200 万像素，用它扫要按分钟算。

`LockBits` 一次性把像素内存复制进 `byte[]`，后面是纯内存循环，快两个数量级：

```powershell
$data = $bmp.LockBits($rect, 'ReadOnly', 'Format32bppArgb')
Marshal::Copy($data.Scan0, $bytes, 0, $bytes.Length)
# 之后 $bytes 里就是 BGRA BGRA BGRA ...
```

---

## 贡献

**这个仓库欢迎任何人改。** 尤其是：

- 🌍 **其他平台的实现** —— macOS（CGEvent / CGWindowList）、Linux（X11 / wayland）
- 🐧 **其他语言的最小实现** —— C、Rust、Go、Python。约定是：一个文件、零依赖、能跑
- 📖 **docs/limits.md 里没写到的失效场景** —— 你踩过的坑就是别人的路标

规矩只有三条：

1. 能跑（附上你验证过的系统版本）
2. 尽量零依赖
3. 注释写给"第一次看 P/Invoke 的人"

PR 直接开，不用先提 issue。

---

## 许可

[MIT](LICENSE)。拿去做任何事，不用问我。

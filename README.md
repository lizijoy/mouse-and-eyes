# mouse-and-eyes

[English](README.en.md) · 中文

Windows 上做 GUI 自动化的最小实现。五个文件，纯 PowerShell 直接调 Win32，不装任何库。

## 为什么写这个

需要让程序替我点一个按钮，试了几个现成的库都没弄顺，干脆自己写一遍，顺便看看底下到底在发生什么。写完觉得可能对别人有点用，就放上来了。

## 有什么

**win/Screen.ps1** — 截图
`GetDC` → `CreateCompatibleBitmap` → `BitBlt`。也能用 `PrintWindow` 抓被挡住的窗口。

**win/Window.ps1** — 找窗口、抢前台
`EnumWindows` 枚举，`AttachThreadInput` 绕前台锁（`SetForegroundWindow` 经常返回成功但没生效）。

**win/Find.ps1** — 在像素里找东西
找色算包围盒，或者拿模板图做朴素匹配。都走 `LockBits` 读内存，`GetPixel` 太慢。

**win/Input.ps1** — 鼠标键盘
`SetCursorPos` + `mouse_event` 点击，`SendInput` 发 Unicode（`keybd_event` 发不了中文）。

**win/Wait.ps1** — 轮询
`Wait-Until`、`Wait-Window`、`Wait-Color`。

`win/Native.ps1` 是全部 P/Invoke 声明，想知道用了哪些 Windows 函数看这一个文件就行。

## 跑一下

```powershell
git clone https://github.com/lizijoy/mouse-and-eyes.git
cd mouse-and-eyes
powershell -ExecutionPolicy Bypass -File .\examples\01-screenshot.ps1
```

`examples/` 里有三个：截屏、找色（默认不点）、抢前台输入中文。

## 效果

拿一个模拟窗口当靶子，找 `#2563EB` 那个蓝按钮，红框是算出来的：

![demo](docs/images/demo-found.png)

```
包围盒: 41,181 - 219,231   179x51，8816 像素，中心 130,206
```

## 实际输出

`01-screenshot.ps1`（2560x1440 的机器）：

```
屏幕范围: 0,0 - 2560,1440  (2560x1440)
截图已保存: ...\mouse-and-eyes-shot.png
截图文件大小: 2321003 bytes
鼠标在 1400,1096，那里的颜色是 #1B191C
```

`02-click-color.ps1`：

```
正在找颜色 #2563EB（容差 12）...

找到了：
  包围盒 : 41,181 - 219,231
  尺寸   : 179 x 51
  中心   : 130, 206
  像素数 : 8816

（dry-run，没有点击。加 -Execute 才会真的点）
```

## 已知问题

这些我都踩过：

- Electron / Chromium 程序找不到控件，只能按坐标点，分辨率一变就废
- 高 DPI（150% 以上）坐标会偏，我没做换算
- 硬件加速渲染的窗口 `PrintWindow` 抓出来是黑的
- `Find-Image` 是暴力匹配，大图上很慢，没优化

## TODO

- [ ] 高 DPI 的坐标换算
- [ ] `Find-Image` 加步长和降采样
- [ ] macOS 版（CGEvent）
- [ ] Linux 的 X11 实现

## 贡献

随便改，PR 直接开，不用先提 issue。

最想要的是其他平台的实现，和其他语言的单文件版本（一个文件、零依赖、能跑就行）。

## License

MIT，拿去用，不用问。

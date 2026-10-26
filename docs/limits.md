# 什么时候会坏

写的时候踩过这些坑，列出来省得别人再踩一遍。

## Chromium / Electron 程序

**症状**：`pywinauto`、UIA、MSAA 全都查不到控件，只能看到一个 `Chrome_WidgetWin_1` 的大窗口。

**原因**：Chrome、Edge、VS Code、Discord、Slack，还有一堆国产桌面端都是 Chromium 内核，整个界面画在一张画布上，对无障碍接口只暴露了很薄的一层。

**后果**：控件级方案（按名字找按钮、读输入框内容）基本没用，只剩坐标点击或视觉模型。坐标点击意味着分辨率、DPI、主题、窗口大小动一个就全废。

## DPI 不是 100%

**症状**：坐标总是差一点，或者模板永远对不上。

**原因**：Windows 有 DPI 虚拟化。150% 缩放下，`GetWindowRect` 给的可能是逻辑像素，而 `SetCursorPos` 用的是物理像素，差 1.5 倍。

检查：

```powershell
# 物理分辨率
(Get-CimInstance Win32_VideoController | Select-Object -First 1).CurrentHorizontalResolution
# 逻辑分辨率
[System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
```

两个数不一样就是开了缩放。这个仓库没做换算。

## 硬件加速的窗口

**症状**：`Get-WindowBitmap` 抓出来全黑。

**原因**：D3D / OpenGL 直接往显卡画，不经过 GDI 表面，PrintWindow 拿不到内容。

**办法**：把窗口搬到前台再截屏，但抢前台本身也不保证成功。

## 锁屏 / 远程桌面断开

**症状**：有人在的时候跑得好好的，一锁屏全乱。

- 锁屏后截图是锁屏界面
- 最小化窗口的 `GetWindowRect` 可能返回奇怪的值
- RDP 断开后会话进入无显示器状态，GDI 截图会失败

要 24 小时跑的别用 GUI 自动化，用服务加 API。必须在交互会话里跑的，保持会话解锁。

## 杀毒软件

自动点鼠标的脚本，行为特征和木马很像。企业环境被拦是正常的，别绕，加白名单或者换方案。

## 大部分情况下别用这个

如果目标系统有 API、有 CLI、能直接读数据库或文件，就用手。有网页的话用 Playwright 操作 DOM，比点像素稳一万倍。

判断顺序：

1. 有官方 API / CLI → 用它
2. 能直接读数据文件 → 用它
3. 有网页 → Playwright / Puppeteer
4. 以上都没有 → 才轮到这堆东西

为了点一个按钮去写 GUI 自动化，而那个按钮背后其实是个 HTTP 请求——这是最常见的浪费时间方式。

# 为什么要有这个仓库

## 一句话

**因为 GUI 自动化的所有框架，底下都是这几个 Windows API。**
把壳剥掉，你看一次就再也不会被框架唬住了。

---

## 我们在解决什么问题

你想让程序替你点一个按钮。听起来简单，但拆开是四件事：

```
看见 → 找到 → 动 → 确认
```

每个环节都有现成的库。但那些库叠在一起之后，你会遇到一种典型的困境：

> 它不工作，但我不知道为什么，也不知道能改哪里。

这个仓库就是给这种时刻准备的。它只有五个原语，每个 100 行上下，
而且全部直接对着 Win32，中间没有任何一层你会怀疑的东西。

---

## 和现有项目的关系

不是替代，是**底层参照**。

| 项目 | 它做了什么 | 和本仓库的关系 |
|------|-----------|---------------|
| [pywinauto](https://github.com/pywinauto/pywinauto) | 把 UIA/MSAA 包装成 Python 对象 | 本仓库只做 Win32 那一层；pywinauto 更该用于原生控件 |
| pyautogui | 截图 + 找图 + 点坐标 | 本仓库是它的手写简化版（找图那段几乎是同一个算法） |
| [microsoft/UFO](https://github.com/microsoft/ufo) | LLM 驱动的 Windows agent，混合 UIA 和视觉 | 重度方案；本仓库适合先理解原理 |
| [microsoft/OmniParser](https://github.com/microsoft/omniparser) | 把截图解析成结构化元素 | 视觉流派；本仓库的"找色"是它的史前版本 |
| [UI-TARS](https://github.com/bytedance/ui-tars) | 端到端 GUI 模型 | 终极方案，但要算力和模型 |

**如果你要做生产工具，去看上面这些。**
**如果你想搞懂它们凭什么能工作，读这个。**

---

## 五个原语，一个不留

### 1. 看（Screen.ps1）

```
GetDC(0) → CreateCompatibleDC → CreateCompatibleBitmap → BitBlt → 存图
```

这几步就是"截图"的全部。OBS、ShareX、录屏软件，底下都是它。

### 2. 找（Window.ps1 + Find.ps1）

窗口是树。`EnumWindows` 给你顶层，每个窗口有句柄、标题、类名、矩形。

在像素里找目标，最原始的两个办法：
- **找色**：扫出某个颜色的包围盒，中心就是可点的地方；
- **找图**：拿一小块模板在大图上滑动比对。

### 3. 动（Input.ps1）

鼠标两步：`SetCursorPos` 定位，`mouse_event` 按下抬起。

键盘有个坑：老的 `keybd_event` 发不了中文（扫描码只有 8 位）。
中文必须走 `SendInput` + `KEYEVENTF_UNICODE`。

### 4. 等（Wait.ps1）

**这是最容易被忽略、但决定成败的一条。**

新手写 `Start-Sleep -Milliseconds 500`，然后祈祷界面在这半秒里加载完。
正确的写法是轮询直到条件成立：

```powershell
Wait-Until -TimeoutMs 15000 -Condition { (Find-Window -TitleLike '完成') -ne $null }
```

猜时间会失效，轮询不会。

### 5. 抢前台（Window.ps1）

Windows 有前台锁：后台程序不能随便把窗口顶上来。
`SetForegroundWindow` 经常"返回成功但没生效"。

解法是 `AttachThreadInput`：临时把本线程挂到前台线程的输入队列上，
用完立刻断开。这是本文档里唯一一段"有技巧"的代码。

---

## 一条重要的经验

**先问"能不能不点界面"。**

很多任务看起来必须点按钮，其实背后是一个 HTTP 请求、
一个命令行工具、或者一个可以直接改的配置文件。

本仓库的作者真实踩过这个坑：
为了在一个容器里执行一条命令，花了半小时研究怎么点它的终端界面，
而最后的正解是 **改一行配置文件让它自己启动**。

**GUI 自动化的成本是 API 的一百倍。先找 API。**

---

## 怎么读这个仓库

建议顺序：

1. `win/Native.ps1` —— 所有 Win32 声明，先看这个知道有哪些弹药
2. `win/Screen.ps1` —— 学"看见"
3. `win/Window.ps1` —— 学"找到窗口"和那段抢前台技巧
4. `win/Input.ps1` —— 学"动"，重点看中文输入那段
5. `win/Find.ps1` —— 学"在像素里找东西"，注意 LockBits 为什么必要
6. `win/Wait.ps1` —— 学"等"
7. `examples/` —— 三个能直接跑的例子

每个文件都是独立的，可以只拿一个去用。

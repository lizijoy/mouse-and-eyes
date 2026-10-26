# mouse-and-eyes

English · [中文](README.md)

Minimal Windows GUI automation. Five files, pure PowerShell calling Win32 directly, no dependencies.

## Why

I needed a program to click a button for me. Tried a few existing libraries, none of them worked the way I wanted, so I wrote it myself and took the chance to see what's actually happening underneath. Figured it might be useful to someone else.

## What's in it

**win/Screen.ps1** — screen capture
`GetDC` → `CreateCompatibleBitmap` → `BitBlt`. Also `PrintWindow` for capturing windows that are covered.

**win/Window.ps1** — find windows, steal foreground
`EnumWindows` to enumerate, `AttachThreadInput` to get around the foreground lock (`SetForegroundWindow` often returns success and does nothing).

**win/Find.ps1** — find things in pixels
Color bounding box, or naive template matching. Both use `LockBits` to read memory — `GetPixel` is way too slow.

**win/Input.ps1** — mouse and keyboard
`SetCursorPos` + `mouse_event` to click, `SendInput` for Unicode (`keybd_event` can't send non-ASCII).

**win/Wait.ps1** — polling
`Wait-Until`, `Wait-Window`, `Wait-Color`.

`win/Native.ps1` holds every P/Invoke declaration. If you want to know which Windows functions this uses, read that one file.

## Running it

```powershell
git clone https://github.com/lizijoy/mouse-and-eyes.git
cd mouse-and-eyes
powershell -ExecutionPolicy Bypass -File .\examples\01-screenshot.ps1
```

Three examples in `examples/`: screenshot, find color (doesn't click by default), steal foreground and type Unicode.

## Result

Mock window as the target, looking for the blue button `#2563EB`. The red box is what the algorithm computed:

![demo](docs/images/demo-found.png)

```
bounds: 41,181 - 219,231   179x51, 8816 px, center 130,206
```

## Real output

`01-screenshot.ps1` (on a 2560x1440 machine):

```
Screen bounds: 0,0 - 2560,1440  (2560x1440)
Saved screenshot: ...\mouse-and-eyes-shot.png
Screenshot size: 2321003 bytes
Cursor at 1400,1096, color there is #1B191C
```

`02-click-color.ps1`:

```
Searching for color #2563EB (tolerance 12)...

Found:
  bounds  : 41,181 - 219,231
  size    : 179 x 51
  center  : 130, 206
  pixels  : 8816

(dry-run, nothing was clicked; pass -Execute to actually click)
```

## Known issues

All of these I ran into:

- Electron / Chromium apps expose no controls — coordinate clicking only, and it breaks the moment resolution changes
- High DPI (150%+) throws the coordinates off; I didn't implement the scaling math
- `PrintWindow` on hardware-accelerated windows gives you a black image
- `Find-Image` is brute force, slow on large images, no optimization

## TODO

- [ ] DPI coordinate conversion
- [ ] `Find-Image`: step size and downsampling
- [ ] macOS version (CGEvent)
- [ ] Linux X11 version

## Contributing

Change whatever you want, open a PR directly, no issue needed.

What I'd most like: other platforms, and single-file implementations in other languages (one file, zero deps, it runs).

## License

MIT. Take it, no need to ask.

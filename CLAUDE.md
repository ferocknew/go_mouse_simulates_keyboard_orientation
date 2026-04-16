# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# macOS（需要 CGO）
CGO_ENABLED=1 go build -o virtualgamepad ./src

# Windows（无需 CGO）
CGO_ENABLED=0 go build -o virtualgamepad.exe ./src
```

macOS 需要辅助功能权限：系统设置 > 隐私与安全性 > 辅助功能，添加终端或二进制。
Windows 无需特殊权限。

无测试、无 linter、无 Makefile。无第三方 Go 依赖。

## Architecture

鼠标 → 8方向键盘映射工具，捕获模式激活时隐藏光标并屏蔽系统鼠标事件。三个子系统协作：

### 1. 平台输入层（鼠标捕获 + 键盘输出 + 光标控制）

通过 Go build tags (`//go:build darwin` / `//go:build windows`) 分离：

**macOS (CGO) — `darwin_input.go` + `darwin.c`/`darwin.h`**

- `CGEventTapCreate` 使用 `kCGEventTapOptionDefault` **拦截模式**
- 事件掩码：`kCGEventMouseMoved` + `kCGEventLeftMouseDragged` + 左/右/中键 Down/Up + `kCGEventKeyDown`
- `eventTapCallback` 回调：
  - 鼠标移动：读取 delta（`kCGMouseEventDeltaX/Y`）累积到 `atomic.Int32`，捕获激活时返回 NULL
  - 鼠标点击：捕获激活时返回 NULL，防止切换到其他应用
  - Ctrl+ESC：触发 Toggle 并返回 NULL
- `reenableEventTap()`：EventTap 超时禁用时重新启用
- `IOHIDManager`（`startHIDManager()`）捕获 HID 层按钮（CGEventTap 捕获不到侧键），过滤 Usage Page `0x09`，usage 1=左键, 2=右键, 3=中键, 4=后退, 5=前进
- `hideCursor()`/`showCursor()`：`CGDisplayHideCursor`/`CGDisplayShowCursor`
- 运行在 `runtime.LockOSThread()` 的独立线程，阻塞于 `CFRunLoopRun()`

**Windows (syscall) — `windows_input.go`（纯 Go，无 CGO）**

- `WH_MOUSE_LL` 低级鼠标钩子：捕获移动 delta（`pt - GetCursorPos()`）+ 左/右/侧键（`WM_XBUTTONDOWN` 的 `mouseData` 高字=1 为后退, =2 为前进）
- `WH_KEYBOARD_LL` 低级键盘钩子：检测 Ctrl+ESC（`GetAsyncKeyState` 检查 Ctrl 状态）
- `SendInput` + `KEYBDINPUT` 输出键盘事件
- `ShowCursor` 是计数器，`HideCursor()` 调用一次递减，`ShowCursor()` 循环 10 次确保显示
- `syscall.NewCallback` 创建回调函数指针
- 消息循环 `GetMessageW` 驱动钩子回调，退出时 `PostThreadMessageW(WM_QUIT)` 打断

**公共接口**（两个平台各自实现）：`KeyDown`/`KeyUp`/`HideCursor`/`ShowCursor`/`CheckAccessibility`/`StartEventTap`

### 2. Tick 循环（方向计算 + 按键输出）— 平台无关

`capture.go` 的 `RunTickLoop` 以 `config.TickInterval` 间隔运行（由 `mouse_sampling_rate` 配置）：
- `atomic.Swap` 取累积增量 → 平滑滤波 → 止动判定（`max(Deadzone, NoiseThreshold)`）→ 惯性滑行/keep_move → `atan2` 计算 8 方向扇区 → 按键状态 diff
- 按键最小保持 `MinKeyHoldMs`（50ms）防止抖动，延迟释放的键保留在 `pressed` map 中直到真正释放
- 键盘输出调用平台无关的 `KeyDown(k)`/`KeyUp(k)`

### Tick 核心判定流程

```
smoothed delta → |delta| < max(Deadzone, NoiseThreshold)?
  ├─ YES → keep_move 模式且 lastDirKeys 非空?
  │   ├─ YES → 保持最后方向键（无限期）
  │   └─ NO  → 惯性滑行中？(time.Since(lastMoveTime) < CoastDuration)
  │       ├─ YES → 保持最后方向键，继续滑行
  │       └─ NO  → releaseAll()，进入 Idle
  └─ NO  → atan2 计算 8 方向扇区 → updateKeys()
```

### 3. 配置解析 — 平台无关

`config.go` 手写 flat YAML 解析。键码映射在 `keys_darwin.go`/`keys_windows.go`（按平台虚拟键码），`defaultConfig()` 通过 `keyNameToCode["up"]` 等查找自动适配平台。

### Threading

- **Main goroutine**: 信号处理 + 状态显示，退出时调用 `ShowCursor()`
- **平台线程** (locked OS thread): macOS CFRunLoop / Windows 消息循环
- **Tick goroutine**: 按 TickInterval 循环处理方向
- 同步：`atomic.Int32` 传递鼠标增量，`sync.Mutex` 保护 active 状态和鼠标按键状态

### CGO 约束（仅 macOS）

- C 代码在 `darwin.c`/`darwin.h`（不能在 Go 的 `import "C"` 块内定义 C 函数，会导致 `//export` 时重复符号）
- `//export` 导出的 Go 函数（`eventTapCallback`、`hidButtonCallback`）必须是包级函数，通过全局变量 `captureRef` 访问 Capture 实例
- 返回 NULL（`C.CGEventRef(unsafe.Pointer(nil))`）用于吞掉/拦截事件

## Configuration

`config.yaml`（当前目录或可执行文件同目录）：

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `mouse_up/down/left/right` | 方向键 | 8方向映射键名 |
| `mouse_button_1/2/4/5` | z/x/v/enter | 鼠标按键（1=左,2=右,4=后退,5=前进） |
| `mouse_sampling_rate` | 1000 | 采样率 Hz，tick 间隔 = 1s/rate |
| `move_inertia_time` | 0.08 | 惯性滑行时间秒，鼠标停住后方向键继续保持的时长 |
| `mouse_reduces_noise` | 0 | 噪声过滤阈值（0=使用 Deadzone），smoothed delta 低于此值视为停止 |
| `keep_move` | false | 停下鼠标后是否无限保持移动方向（跳过惯性滑行超时） |

键名支持：a-z, 0-9, 方向键(up/down/left/right), 功能键(enter/space/esc/tab/delete), 修饰键(shift/ctrl/alt/cmd)。

## Key Constants (capture.go)

- `Deadzone = 2`: 鼠标增量基础死区
- `SmoothFactor = 0.2`: 平滑权重（prev * 0.2 + cur * 0.8）
- `MinKeyHoldMs = 50`: 按键最小保持时间（ms）

## Config Struct (config.go)

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| MouseUp/Down/Left/Right | uint16 | 方向键 | 8方向映射 |
| MouseLeftButton/RightButton | uint16 | z/x | 鼠标左右键映射 |
| MouseBackButton/ForwardBtn | uint16 | v/enter | 侧键映射 |
| TickInterval | Duration | 1ms | 由 mouse_sampling_rate 计算 |
| CoastDuration | Duration | 80ms | 惯性滑行时长 |
| NoiseThreshold | float64 | 0 | 噪声阈值（0=使用 Deadzone） |
| KeepMove | bool | false | 停下鼠标后保持移动方向 |

## CI/CD

`.github/workflows/release.yml`：推送 tag 触发，编译 macOS ARM + Windows x64，打包 ZIP（含 config.yaml），创建 GitHub Release。

```bash
# 发布新版本
cat VERSION  # 确认版本号
git tag x.y.z && git push origin x.y.z
```

tag 不带 v 前缀。`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` 消除 Node.js 弃用警告，`cache: false` 跳过无 go.sum 的缓存警告。

Windows 构建用 `CGO_ENABLED=0`（纯 Go），无需 MinGW。macOS 构建需要 CGO。

## 项目结构

```
├── config.yaml
├── VERSION
├── go.mod
├── CLAUDE.md
├── .github/workflows/release.yml
├── src/
│   ├── main.go          # 入口：信号处理 + 状态显示
│   ├── capture.go       # 核心逻辑：tick 循环、方向计算、按键管理（平台无关）
│   ├── config.go        # 配置解析（平台无关）
│   ├── darwin_input.go  # macOS CGO 桥接：CGEventTap/IOHIDManager 回调
│   ├── darwin.c         # macOS C 层：EventTap、HID、光标、键盘输出
│   ├── darwin.h         # macOS C 头文件
│   ├── keys_darwin.go   # macOS 虚拟键码映射
│   ├── windows_input.go # Windows 纯 Go syscall：低级钩子、SendInput
│   └── keys_windows.go  # Windows VK 码映射
```

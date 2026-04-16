# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
CGO_ENABLED=1 go build -o virtualgamepad ./src
./virtualgamepad
```

需要 macOS 辅助功能权限：系统设置 > 隐私与安全性 > 辅助功能，添加终端或二进制。

无测试、无 linter、无 Makefile。无第三方 Go 依赖。

## Architecture

鼠标 → 8方向键盘映射工具，捕获模式激活时隐藏光标并屏蔽系统鼠标事件。三个子系统协作：

### 1. CGEventTap（鼠标移动 + 点击拦截 + 键盘热键）
- `darwin.c` 创建 `CGEventTapCreate`，使用 `kCGEventTapOptionDefault` **拦截模式**（非监听）
- 事件掩码：`kCGEventMouseMoved` + `kCGEventLeftMouseDragged` + 左/右/中键 Down/Up + `kCGEventKeyDown`
- `darwin_input.go` 的 `//export eventTapCallback` 回调：
  - 鼠标移动：读取 delta 累积到 `atomic.Int32`，捕获激活时返回 NULL 吞掉事件
  - 鼠标点击：捕获激活时返回 NULL 吞掉，防止点击切换到其他应用
  - Ctrl+ESC：触发 Toggle 并返回 NULL
- `hideCursor()`/`showCursor()`：`CGDisplayHideCursor`/`CGDisplayShowCursor`，Toggle 时联动
- `reenableEventTap()`：EventTap 超时禁用时重新启用（使用正确的 eventTapPort）
- 运行在 `runtime.LockOSThread()` 的独立线程上，阻塞于 `CFRunLoopRun()`

### 2. IOHIDManager（鼠标按键，包括侧键）
- `darwin.c` 的 `startHIDManager()` 捕获 HID 层按钮事件（CGEventTap 捕获不到侧键）
- 过滤 Usage Page `0x09`，usage 1=左键, 2=右键, 3=中键, 4=后退, 5=前进
- `darwin_input.go` 的 `//export hidButtonCallback` 回调到 `HandleMouseButton`

### 3. Tick 循环（方向计算 + 按键输出）
- `capture.go` 的 `RunTickLoop` 以 `config.TickInterval` 间隔运行（由 `mouse_sampling_rate` 配置）
- 流程：`atomic.Swap` 取累积增量 → 平滑滤波 → 止动判定（`max(Deadzone, NoiseThreshold)`）→ 惯性滑行 → `atan2` 计算 8 方向扇区 → 按键状态 diff
- 按键最小保持 `MinKeyHoldMs`（50ms）防止抖动，延迟释放的键保留在 `pressed` map 中直到真正释放
- 键盘输出通过 C 函数 `sendKeyDown`/`sendKeyUp` → `CGEventPost(kCGHIDEventTap)`

### Tick 核心判定流程

```
smoothed delta → |delta| < max(Deadzone, NoiseThreshold)?
  ├─ YES → 惯性滑行中？(time.Since(lastMoveTime) < CoastDuration)
  │   ├─ YES → 保持最后方向键，继续滑行
  │   └─ NO  → releaseAll()，进入 Idle
  └─ NO  → atan2 计算 8 方向扇区 → updateKeys()
```

### Threading
- **Main goroutine**: 信号处理 + 状态显示，退出时调用 `ShowCursor()`
- **CFRunLoop 线程** (locked OS thread): CGEventTap + IOHIDManager
- **Tick goroutine**: 按 TickInterval 循环处理方向
- 同步：`atomic.Int32` 传递鼠标增量，`sync.Mutex` 保护 active 状态和鼠标按键状态

### CGO 约束
- C 代码在 `darwin.c`/`darwin.h`（不能在 Go 的 `import "C"` 块内定义 C 函数，会导致 `//export` 时重复符号）
- `//export` 导出的 Go 函数（`eventTapCallback`、`hidButtonCallback`）必须是包级函数，通过全局变量 `captureRef` 访问 Capture 实例
- 返回 NULL（`C.CGEventRef(unsafe.Pointer(nil))`）用于吞掉/拦截事件

## Configuration

`config.yaml`（当前目录或可执行文件同目录），手写 flat YAML 解析。配置项：

- `mouse_up/down/left/right`: 方向映射键名
- `mouse_button_1/2/4/5`: 鼠标按键映射（1=左,2=右,4=后退,5=前进）
- `mouse_sampling_rate`: 采样率 Hz（默认 1000），决定 tick 间隔 = 1s/rate
- `move_inertia_time`: 惯性滑行时间秒（默认 0.08），鼠标停住后方向键继续保持的时长
- `mouse_reduces_noise`: 噪声过滤阈值（默认 0=禁用），smoothed delta 低于此值视为停止而非方向抖动

键名定义在 `config.go` 的 `keyNameToCode` map 中（a-z, 0-9, 方向键, 功能键, 修饰键）。

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

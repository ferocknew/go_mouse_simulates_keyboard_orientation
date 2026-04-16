# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
CGO_ENABLED=1 go build -o virtualgamepad .
./virtualgamepad
```

需要 macOS 辅助功能权限：系统设置 > 隐私与安全性 > 辅助功能，添加终端或二进制。

无测试、无 linter、无 Makefile。无第三方 Go 依赖。

## Architecture

鼠标 → 8方向键盘映射工具，三个子系统协作：

### 1. CGEventTap（鼠标移动 + 键盘热键）
- `darwin.c` 创建 `CGEventTapCreate`，监听 `kCGEventMouseMoved` + `kCGEventKeyDown`
- `darwin_input.go` 的 `//export eventTapCallback` 回调：鼠标增量原子累积到 `atomic.Int32`，Ctrl+ESC 触发 Toggle
- 运行在 `runtime.LockOSThread()` 的独立线程上，阻塞于 `CFRunLoopRun()`

### 2. IOHIDManager（鼠标按键，包括侧键）
- `darwin.c` 的 `startHIDManager()` 捕获 HID 层按钮事件（CGEventTap 捕获不到侧键）
- 过滤 Usage Page `0x09`，usage 1=左键, 2=右键, 3=中键, 4=后退, 5=前进
- `darwin_input.go` 的 `//export hidButtonCallback` 回调到 `HandleMouseButton`

### 3. Tick 循环（方向计算 + 按键输出）
- `capture.go` 的 `RunTickLoop` 以 1ms tick 运行
- 流程：`atomic.Swap` 取累积增量 → 灵敏度缩放 → 平滑滤波 → Deadzone → `atan2` 计算 8 方向扇区 → 按键状态 diff
- 按键最小保持 20ms（`MinKeyHoldMs`）防止抖动
- 键盘输出通过 C 函数 `sendKeyDown`/`sendKeyUp` → `CGEventPost(kCGHIDEventTap)`

### Threading
- **Main goroutine**: 信号处理 + 状态显示
- **CFRunLoop 线程** (locked OS thread): CGEventTap + IOHIDManager
- **Tick goroutine**: 1ms 循环处理方向
- 同步：`atomic.Int32` 传递鼠标增量，`sync.Mutex` 保护 active 状态和鼠标按键状态

### CGO 约束
- C 代码在 `darwin.c`/`darwin.h`（不能在 Go 的 `import "C"` 块内定义 C 函数，会导致 `//export` 时重复符号）
- `//export` 导出的 Go 函数（`eventTapCallback`、`hidButtonCallback`）必须是包级函数，通过全局变量 `captureRef` 访问 Capture 实例

## Configuration

`config.yaml`（当前目录或可执行文件同目录），手写 flat YAML 解析。配置项：

- `mouse_up/down/left/right`: 方向映射键名
- `mouse_button_1/2/4/5`: 鼠标按键映射（1=左,2=右,4=后退,5=前进）
- `move_speed`: 灵敏度倍率（默认 1.0）

键名定义在 `config.go` 的 `keyNameToCode` map 中（a-z, 0-9, 方向键, 功能键, 修饰键）。

## Key Constants (capture.go)

- `Deadzone = 2`: 鼠标增量小于此值忽略
- `SmoothFactor = 0.2`: 平滑权重
- `MinKeyHoldMs = 20`: 按键最小保持时间
- `TickInterval = time.Millisecond`: tick 间隔

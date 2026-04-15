# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Xcode 项目，使用 Xcode 打开 `VirtualGamepadDemo.xcodeproj` 构建。无 CLI 构建脚本、无测试、无 lint。

关键构建设置：`ENABLE_APP_SANDBOX = NO`（CGEventTap 要求关闭沙箱）。

## Architecture

macOS 虚拟手柄应用：拦截鼠标输入，通过 CGEvent 模拟键盘事件（非 IOHIDUserDevice，避免受限授权）。

数据流：**鼠标 → MouseInterceptor → GamepadController → KeySimulator → 键盘事件**

### 核心文件

| 文件 | 职责 |
|------|------|
| `gamepad_controller.swift` | 主协调器（@MainActor @Observable），整合所有组件，125Hz DispatchSourceTimer 报告循环 |
| `mouse_interceptor.swift` | CGEventTap 拦截鼠标事件，独立线程运行，回调返回 `nil` 消耗事件 |
| `key_simulator.swift` | CGEvent 键盘事件发送，维护 pressedKeys 状态 |
| `input_mapper.swift` | DirectionState：累积鼠标 delta → 方向判定（阈值 + 衰减） |
| `keyboard_monitor.swift` | NSEvent 监听 Ctrl+Esc 热键（全局 + 本地） |
| `ContentView.swift` | SwiftUI 界面：摇杆可视化、按钮状态、灵敏度滑块 |
| `VirtualGamepadDemoApp.swift` | App 入口，注入 GamepadController 环境 |

### 输入映射

鼠标移动 → WASD + 箭头键（同时输出摇杆和 D-pad），鼠标左/右/中/侧键 → J/K/U/I。

### Concurrency 注意事项

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`：所有类型默认 MainActor 隔离
- 后台线程（MouseInterceptor 线程、DispatchSourceTimer）访问的属性/方法需标记 `nonisolated(unsafe)` 或 `nonisolated`
- CGEventTap 回调必须是全局函数或无捕获闭包
- `CGAssociateMouseAndMouseCursorPosition` 参数是 `Int32`（boolean_t），不是 `Bool`

# VirtualGamepadDemo - 项目开发记录

## 项目概述

macOS 虚拟手柄应用：拦截鼠标操作，转换为游戏手柄输入（键盘模拟方式）。

## 最终架构（方案C：键盘模拟）

不使用 IOHIDUserDevice（需要受限授权），改用 CGEvent 模拟键盘事件，无需特殊授权，可分发到任意 Mac。

### 文件结构

| 文件 | 职责 |
|------|------|
| `key_simulator.swift` | CGEvent 键盘事件发送（press/release/releaseAll） |
| `input_mapper.swift` | DirectionState - 鼠标 delta → 方向状态（阈值+衰减） |
| `mouse_interceptor.swift` | CGEventTap 拦截鼠标事件，支持额外按钮回调 |
| `keyboard_monitor.swift` | NSEvent 全局/本地监听 Ctrl+Esc 热键 |
| `gamepad_controller.swift` | 主协调器：整合所有组件，125Hz 报告循环 |
| `ContentView.swift` | SwiftUI 界面：摇杆可视化、按钮状态、灵敏度调节 |

### 输入映射

| 鼠标操作 | 模拟按键 | 手柄功能 |
|----------|---------|---------|
| 鼠标移动 | W/A/S/D + 箭头键 | 摇杆 + 方向键 |
| 左键 | J | A 按钮 |
| 右键 | K | B 按钮 |
| 中键 | U | C 按钮 |
| 侧键(button4) | I | D 按钮 |
| Ctrl+Esc | - | 捕获/释放切换 |

### 关键技术点

- **CGEventTap**: `.cgSessionEventTap` + `.defaultTap`，回调返回 `nil` 消耗事件
- **CGAssociateMouseAndMouseCursorPosition**: 参数是 `Int32`(boolean_t)，不是 `Bool`
- **CGEventTap 回调**: 必须是全局函数或无捕获闭包，不能引用实例方法
- **方向判断**: 累积鼠标 delta，超过阈值按住方向键，衰减后低于释放阈值松开
- **125Hz 循环**: DispatchSourceTimer 消费累积 delta → 更新方向 → 发送按键

## 构建配置

- `ENABLE_APP_SANDBOX = NO`（CGEventTap 必须关闭沙箱）
- 仅 macOS 平台（`SUPPORTED_PLATFORMS = macosx`）
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（Xcode 26.4 默认）

## 踩过的坑

### 1. IOHIDUserDevice 需要受限授权

- `IOHIDUserDeviceCreateWithProperties` 需要 `com.apple.developer.hid.virtual.device` 授权
- 这是 Apple 受限授权，需付费开发者账号 + Apple 审批
- Ad-hoc 签名也无效，最终放弃该方案

### 2. IOKit API 名称与文档不一致

- 旧文档提到 `IOHIDUserDeviceCreate`，SDK 中只有 `IOHIDUserDeviceCreateWithProperties`
- `IOHIDUserDeviceScheduleWithRunLoop` → 应使用 `IOHIDUserDeviceSetDispatchQueue` + `IOHIDUserDeviceActivate`
- `IOHIDUserDeviceHandleReport` → `IOHIDUserDeviceHandleReportWithTimeStamp`
- `IOHIDUserDeviceRef` 在 Swift 中重命名为 `IOHIDUserDevice`
- Bridging Header 路径: `IOKit/hidsystem/IOHIDUserDevice.h`（不是 `IOKit/hid/`）

### 3. Xcode 26.4 Swift 并发

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`：所有类型默认 MainActor 隔离
- 后台线程访问的属性需 `nonisolated(unsafe)`
- 后台线程访问的方法需 `nonisolated`
- `@Observable` + `@Environment` 的 binding 需通过 `@Bindable` 子视图

### 4. CGEventTap 已知问题

- 返回 `nil` 不能完全可靠地抑制鼠标移动事件（Radar #14123633）
- 使用 `CGAssociateMouseAndMouseCursorPosition(0)` 分离光标作为主要方案

## 项目状态

- 编译通过，方案C（键盘模拟）可用
- 不需要特殊授权，只需辅助功能权限
- 可分发到其他 Mac 使用

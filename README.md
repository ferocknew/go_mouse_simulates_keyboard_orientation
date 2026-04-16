# 🎮 VirtualGamepad

鼠标 → 8方向键盘映射工具。把鼠标当成模拟摇杆，映射成数字方向键。

## 快速开始

```bash
CGO_ENABLED=1 go build -o virtualgamepad ./src
./virtualgamepad
```

需要 macOS 辅助功能权限：系统设置 > 隐私与安全性 > 辅助功能。

## 操作

| 操作 | 功能 |
|---|---|
| 移动鼠标 | 映射为 8 方向按键（持续移动 = 持续 KeyDown） |
| 鼠标按键 | 映射为配置的键盘按键 |
| Ctrl+ESC | 切换捕获模式（开启时隐藏光标并屏蔽系统鼠标） |
| Ctrl+C | 退出 |

## 方向映射

```
        ↑          ↗ = ↑ + →
    ↖       ↗      ↖ = ↑ + ←
  ←     ●     →    ↙ = ↓ + ←
    ↙       ↘      ↘ = ↓ + →
        ↓
```

使用 `atan2(dy, dx)` 计算角度，每 45° 一个扇区，共 8 方向。

## 配置文件 config.yaml

```yaml
# 方向映射
mouse_up: up
mouse_down: down
mouse_left: left
mouse_right: right

# 鼠标按键映射（1=左键, 2=右键, 4=后退侧键, 5=前进侧键）
mouse_button_1: x
mouse_button_2: z
mouse_button_4: v
mouse_button_5: enter

# 采样率（Hz），决定检测鼠标移动的频率
mouse_sampling_rate: 500

# 惯性滑行（秒），鼠标停住后方向键继续保持的时长
move_inertia_time: 0.3

# 噪声过滤，smoothed delta 低于此值视为停止（过滤手抖）
mouse_reduces_noise: 0.2
```

键名支持：a-z, 0-9, 方向键(up/down/left/right), 功能键(enter/space/esc/tab/delete), 修饰键(shift/ctrl/alt/cmd)。

## 核心机制

### 采样 → 止动判定 → 方向输出

每个 tick（间隔 = 1s / sampling_rate）：

1. 取累积鼠标 delta → 平滑滤波
2. 止动判定：`|delta| < max(Deadzone, NoiseThreshold)` → 视为停止
3. 停止时进入惯性滑行（保持最后方向键，持续 move_inertia_time）
4. 滑行超时 → releaseAll
5. 未停止 → `atan2` 算方向 → 按键状态 diff 输出

### 鼠标事件屏蔽

捕获模式激活时：
- CGEventTap 以拦截模式运行，吞掉鼠标移动和点击事件（返回 NULL）
- `CGDisplayHideCursor` 隐藏光标
- 鼠标按键通过 IOHIDManager（HID 层）捕获，不受 CGEventTap 拦截影响

### 按键防抖

- `MinKeyHoldMs = 50ms`：按键按下后至少保持 50ms 才能释放
- 延迟释放的键保留在跟踪 map 中，防止丢失 KeyUp

## 项目结构

```
├── config.yaml          # 配置文件
├── go.mod               # Go module
├── CLAUDE.md            # Claude Code 开发指引
├── src/
│   ├── main.go          # 入口：信号处理 + 状态显示
│   ├── capture.go       # 核心逻辑：tick 循环、方向计算、按键管理
│   ├── config.go        # 配置解析
│   ├── darwin_input.go  # CGO 桥接：CGEventTap/IOHIDManager 回调
│   ├── darwin.c         # macOS C 层：EventTap、HIDManager、光标、键盘输出
│   └── darwin.h         # C 头文件
```

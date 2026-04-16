## 项目说明


# 🎮 鼠标 → 8方向键（↑↓←→）映射方案（Go 跨平台）

---

# 📌 一、目标（重新定义）

实现：

* 鼠标移动 → 映射为 8方向：

  * ↑ ↓ ← →
  * ↖ ↗ ↙ ↘
* 输出键盘：

  * 方向键组合（例如 ↑ + →）
* 鼠标持续移动 → 持续 KeyDown
* 停止移动 → KeyUp

---

# 🧠 二、核心思路（关键）

## 👉 不再用“阈值判断轴”

而是：

> 🎯 使用“向量角度（Angle）”判断方向

---

# 📐 三、方向计算（核心算法）

## 输入：

```go
dx := input.DeltaX
dy := input.DeltaY
```

---

## 1️⃣ 计算角度

```go
angle := math.Atan2(float64(dy), float64(dx)) // -π ~ π
```

---

## 2️⃣ 转换为 8方向（每45°）

```go
sector := int(math.Round(angle / (math.Pi / 4))) % 8
```

---

## 3️⃣ 映射表

```go
var directions = map[int][]string{
    0: {"Right"},
    1: {"Down", "Right"},
    2: {"Down"},
    3: {"Down", "Left"},
    4: {"Left"},
    5: {"Up", "Left"},
    6: {"Up"},
    7: {"Up", "Right"},
}
```

---

# 🎮 四、输出逻辑（关键区别）

## ❗不是 KeyTap（按一下）

而是：

> ✔ KeyDown（按住）
> ✔ KeyUp（释放）

---

## 状态管理（重点）

```go
type KeyState struct {
    pressed map[string]bool
}
```

---

## 更新逻辑

```go
func UpdateKeys(newKeys []string, state *KeyState) {

    newSet := make(map[string]bool)
    for _, k := range newKeys {
        newSet[k] = true
    }

    // 释放旧键
    for k := range state.pressed {
        if !newSet[k] {
            KeyUp(k)
        }
    }

    // 按下新键
    for k := range newSet {
        if !state.pressed[k] {
            KeyDown(k)
        }
    }

    state.pressed = newSet
}
```

---

# 🧊 五、Deadzone（防抖）

```go
func IsZero(dx, dy int) bool {
    return abs(dx) < 2 && abs(dy) < 2
}
```

👉 如果静止：

```go
ReleaseAllKeys()
```

---

# ⚡ 六、完整主循环

```go
for {
    dx, dy := ReadMouseDelta()

    if IsZero(dx, dy) {
        ReleaseAllKeys()
        continue
    }

    angle := math.Atan2(float64(dy), float64(dx))
    sector := int(math.Round(angle / (math.Pi / 4))) & 7

    keys := directions[sector]

    UpdateKeys(keys, &state)
}
```

---

# 🎛 七、UI 配置（重点）

## 配置文件

```json
{
  "bindings": {
    "Up": "up",
    "Down": "down",
    "Left": "left",
    "Right": "right"
  },
  "deadzone": 2,
  "sensitivity": 1.0
}
```

---

## UI 功能

### ✔ 按键映射

* ↑ → 可改为 W
* ↓ → 可改为 S

---

### ✔ 参数调节

* Deadzone
* 灵敏度
* 响应速度

---

# 🧱 八、平台实现

## 🍎 macOS

* 输入：CGEventTap
* 输出：CGEvent（KeyDown / KeyUp）

---

## 🪟 Windows

* 输入：Raw Input
* 输出：SendInput

---

# ⚠️ 九、关键细节（容易踩坑）

## ❗ 1. 对角方向必须同时按两个键

例如：

```text
↗ = Up + Right
```

---

## ❗ 2. 不要频繁 KeyTap

错误：

```text
Up Down Up Down Up Down
```

正确：

```text
KeyDown → 持续 → KeyUp
```

---

## ❗ 3. 必须做状态缓存

否则会：

* 键盘抖动
* 输入卡顿

---

## ❗ 4. 鼠标必须用“增量”（delta）

不能用：

```text
绝对坐标
```

必须用：

```text
移动变化 dx/dy
```

---

# 🚀 十、进阶优化（强烈建议）

## 🎯 1. 灵敏度曲线

```go
dx *= sensitivity
dy *= sensitivity
```

---

## 🎯 2. 平滑（防抖）

```go
dx = Smooth(prevX, dx, 0.2)
dy = Smooth(prevY, dy, 0.2)
```

---

## 🎯 3. 方向锁定（高级）

防止：

```text
↗ ↘ ↗ ↘ 抖动
```

👉 加 hysteresis（滞后）

---

# 🎯 十一、总结

👉 鼠标 → 8方向 = 用“角度”
👉 持续输入 = 用 KeyDown / KeyUp
👉 核心是状态机，不是触发器

---

# 🧠 一句话核心

> “把鼠标当成一个模拟摇杆（Analog Stick），再映射成数字方向键”

---

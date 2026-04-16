package main

import (
	"fmt"
	"math"
	"sync"
)

// macOS 方向键虚拟键码
const (
	VKUp    uint16 = 0x7E // 126
	VKDown  uint16 = 0x7D // 125
	VKLeft  uint16 = 0x7B // 123
	VKRight uint16 = 0x7C // 124
)

// 8 方向扇区 → 按键映射
var directionKeys = map[int][]uint16{
	0: {VKRight},          // →
	1: {VKDown, VKRight},  // ↘
	2: {VKDown},           // ↓
	3: {VKDown, VKLeft},   // ↙
	4: {VKLeft},           // ←
	5: {VKUp, VKLeft},     // ↖
	6: {VKUp},             // ↑
	7: {VKUp, VKRight},    // ↗
}

var directionNames = map[int]string{
	0: "→ Right",
	1: "↘ Down-Right",
	2: "↓ Down",
	3: "↙ Down-Left",
	4: "← Left",
	5: "↖ Up-Left",
	6: "↑ Up",
	7: "↗ Up-Right",
}

const Deadzone = 2

type Capture struct {
	mu      sync.Mutex
	active  bool
	pressed map[uint16]bool
	dirName string
}

func NewCapture() *Capture {
	return &Capture{
		active:  true,
		pressed: make(map[uint16]bool),
		dirName: "Idle",
	}
}

func (c *Capture) Toggle() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.active = !c.active
	if !c.active {
		c.releaseAll()
	}
	if c.active {
		fmt.Println("\n✅ 捕获已开启")
	} else {
		fmt.Println("\n❌ 捕获已关闭")
	}
}

func (c *Capture) UpdateMouseDelta(dx, dy int64) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.active {
		return
	}

	// Deadzone 检查
	if abs64(dx) < Deadzone && abs64(dy) < Deadzone {
		c.releaseAll()
		c.dirName = "Idle"
		return
	}

	// 计算角度和方向扇区
	angle := math.Atan2(float64(dy), float64(dx))
	sector := int(math.Round(angle / (math.Pi / 4)))
	sector = ((sector % 8) + 8) % 8

	// 更新按键状态
	newKeys := directionKeys[sector]
	c.updateKeys(newKeys)
	c.dirName = directionNames[sector]
}

func (c *Capture) updateKeys(newKeys []uint16) {
	newSet := make(map[uint16]bool, len(newKeys))
	for _, k := range newKeys {
		newSet[k] = true
	}

	// 释放不再需要的旧键
	for k := range c.pressed {
		if !newSet[k] {
			KeyUp(k)
		}
	}

	// 按下新键
	for k := range newSet {
		if !c.pressed[k] {
			KeyDown(k)
		}
	}

	c.pressed = newSet
}

func (c *Capture) releaseAll() {
	for k := range c.pressed {
		KeyUp(k)
	}
	c.pressed = make(map[uint16]bool)
}

func (c *Capture) PrintStatus() {
	c.mu.Lock()
	defer c.mu.Unlock()

	status := "OFF"
	if c.active {
		status = "ON"
	}
	fmt.Printf("\r[%s] %s          ", status, c.dirName)
}

func abs64(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

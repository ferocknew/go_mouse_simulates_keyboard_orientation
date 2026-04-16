package main

import (
	"fmt"
	"log"
	"math"
	"sync"
)

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
	cfg     *Config

	// 8 方向扇区 → 按键映射（从配置生成）
	directionKeys map[int][]uint16

	// 鼠标按键状态
	mouseButtons map[int]bool
}

func NewCapture(cfg *Config) *Capture {
	// 从配置构建 8 方向映射
	dirKeys := map[int][]uint16{
		0: {cfg.MouseRight},             // →
		1: {cfg.MouseDown, cfg.MouseRight},  // ↘
		2: {cfg.MouseDown},              // ↓
		3: {cfg.MouseDown, cfg.MouseLeft},   // ↙
		4: {cfg.MouseLeft},              // ←
		5: {cfg.MouseUp, cfg.MouseLeft},     // ↖
		6: {cfg.MouseUp},                // ↑
		7: {cfg.MouseUp, cfg.MouseRight},    // ↗
	}

	return &Capture{
		active:        true,
		pressed:       make(map[uint16]bool),
		dirName:       "Idle",
		cfg:           cfg,
		directionKeys: dirKeys,
		mouseButtons:  make(map[int]bool),
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
	newKeys := c.directionKeys[sector]
	c.updateKeys(newKeys)
	newDir := directionNames[sector]
	if c.dirName != newDir {
		log.Printf("[DIR] dx=%d dy=%d angle=%.1f° sector=%d → %s", dx, dy, angle*180/math.Pi, sector, newDir)
	}
	c.dirName = newDir
}

// HandleMouseButton 处理鼠标按键事件
func (c *Capture) HandleMouseButton(button int, down bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.active {
		return
	}

	var keyCode uint16
	switch button {
	case 0: // 左键
		keyCode = c.cfg.MouseLeftButton
	case 1: // 右键
		keyCode = c.cfg.MouseRightButton
	case 3: // 后退键 (Button 4)
		keyCode = c.cfg.MouseBackButton
	case 4: // 前进键 (Button 5)
		keyCode = c.cfg.MouseForwardBtn
	default:
		return
	}

	if keyCode == 0 {
		return
	}

	if down {
		if !c.mouseButtons[button] {
			KeyDown(keyCode)
			c.mouseButtons[button] = true
			log.Printf("[MOUSE] Button %d DOWN → keyCode 0x%02X", button, keyCode)
		}
	} else {
		if c.mouseButtons[button] {
			KeyUp(keyCode)
			delete(c.mouseButtons, button)
			log.Printf("[MOUSE] Button %d UP → keyCode 0x%02X", button, keyCode)
		}
	}
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

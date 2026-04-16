package main

import (
	"fmt"
	"log"
	"math"
	"sync"
	"sync/atomic"
	"time"
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

const (
	Deadzone     = 2
	SmoothFactor = 0.2
	MinKeyHoldMs = 50 // 按键最小保持时间
)

type Capture struct {
	active  bool
	dirName string
	cfg     *Config

	// 8 方向扇区 → 按键映射（从配置生成）
	directionKeys map[int][]uint16

	// 鼠标增量（原子累积）
	accumDx atomic.Int32
	accumDy atomic.Int32

	// 按键状态（tick loop 独占，无需锁）
	pressed    map[uint16]bool
	keySince   map[uint16]time.Time // 每个按键按下的时间

	// 鼠标按键状态
	mu              sync.Mutex
	mouseButtons    map[int]bool
	mouseBtnSince   map[int]time.Time

	// 平滑
	prevDx float64
	prevDy float64

	// 惯性滑行
	lastMoveTime time.Time
	lastDirKeys  []uint16

	// 控制
	muActive sync.Mutex
}

func NewCapture(cfg *Config) *Capture {
	dirKeys := map[int][]uint16{
		0: {cfg.MouseRight},
		1: {cfg.MouseDown, cfg.MouseRight},
		2: {cfg.MouseDown},
		3: {cfg.MouseDown, cfg.MouseLeft},
		4: {cfg.MouseLeft},
		5: {cfg.MouseUp, cfg.MouseLeft},
		6: {cfg.MouseUp},
		7: {cfg.MouseUp, cfg.MouseRight},
	}

	return &Capture{
		active:        true,
		pressed:       make(map[uint16]bool),
		keySince:      make(map[uint16]time.Time),
		dirName:       "Idle",
		cfg:           cfg,
		directionKeys: dirKeys,
		mouseButtons:  make(map[int]bool),
		mouseBtnSince: make(map[int]time.Time),
	}
}

// AddDelta 由 CGEventTap 回调调用，原子累积鼠标增量
func (c *Capture) AddDelta(dx, dy int64) {
	c.accumDx.Add(int32(dx))
	c.accumDy.Add(int32(dy))
}

// RunTickLoop 在独立 goroutine 中运行 tick 循环
func (c *Capture) RunTickLoop(done <-chan struct{}) {
	ticker := time.NewTicker(c.cfg.TickInterval)
	defer ticker.Stop()

	for {
		select {
		case <-done:
			c.releaseAll()
			return
		case <-ticker.C:
			c.tick()
		}
	}
}

func (c *Capture) tick() {
	c.muActive.Lock()
	active := c.active
	c.muActive.Unlock()

	if !active {
		return
	}

	// 取出并重置累积增量
	dx := int64(c.accumDx.Swap(0))
	dy := int64(c.accumDy.Swap(0))

	// 平滑（只在有数据时混合，无数据时衰减）
	var sdx, sdy float64
	if dx != 0 || dy != 0 {
		sdx = c.smooth(c.prevDx, float64(dx))
		sdy = c.smooth(c.prevDy, float64(dy))
	} else {
		// 没有新数据，使用上一次的值衰减
		sdx = c.prevDx * 0.8
		sdy = c.prevDy * 0.8
	}
	c.prevDx = sdx
	c.prevDy = sdy

	// 止动判定：使用 max(Deadzone, NoiseThreshold) 作为有效阈值
	threshold := math.Max(float64(Deadzone), c.cfg.NoiseThreshold)
	if math.Abs(sdx) < threshold && math.Abs(sdy) < threshold {
			// keep_move 模式：无限保持最后方向
			if c.cfg.KeepMove && len(c.lastDirKeys) > 0 {
				c.updateKeys(c.lastDirKeys)
				return
			}
		// 惯性滑行：鼠标停住后，方向键继续保持一段时间再释放
		if len(c.lastDirKeys) > 0 && time.Since(c.lastMoveTime) < c.cfg.CoastDuration {
			c.updateKeys(c.lastDirKeys)
			return
		}
		c.releaseAll()
		c.dirName = "Idle"
		c.lastDirKeys = nil
		return
	}

	// 计算方向
	angle := math.Atan2(sdy, sdx)
	sector := int(math.Round(angle / (math.Pi / 4)))
	sector = ((sector % 8) + 8) % 8

	newKeys := c.directionKeys[sector]
	c.updateKeys(newKeys)

	// 记录有效移动，用于惯性滑行
	c.lastMoveTime = time.Now()
	c.lastDirKeys = newKeys

	newDir := directionNames[sector]
	if c.dirName != newDir {
		log.Printf("[DIR] raw=(%d,%d) smooth=(%.1f,%.1f) angle=%.1f° → %s", dx, dy, sdx, sdy, angle*180/math.Pi, newDir)
	}
	c.dirName = newDir
}

func (c *Capture) smooth(prev, cur float64) float64 {
	return prev*SmoothFactor + cur*(1-SmoothFactor)
}

func (c *Capture) updateKeys(newKeys []uint16) {
	now := time.Now()
	newSet := make(map[uint16]bool, len(newKeys))
	for _, k := range newKeys {
		newSet[k] = true
	}

	// 释放旧键（检查最小保持时间）
	for k := range c.pressed {
		if !newSet[k] {
			if since, ok := c.keySince[k]; ok {
				if now.Sub(since) < MinKeyHoldMs*time.Millisecond {
					newSet[k] = true // 保持：留在 pressed 中，下个 tick 继续检查
					continue
				}
			}
			KeyUp(k)
			delete(c.keySince, k)
		}
	}

	// 按下新键
	for k := range newSet {
		if !c.pressed[k] {
			KeyDown(k)
			c.keySince[k] = now
		}
	}

	c.pressed = newSet
}

func (c *Capture) releaseAll() {
	for k := range c.pressed {
		KeyUp(k)
	}
	c.pressed = make(map[uint16]bool)
	c.keySince = make(map[uint16]time.Time)
}

// Toggle 切换捕获状态
func (c *Capture) Toggle() {
	c.muActive.Lock()
	defer c.muActive.Unlock()
	c.active = !c.active
	if !c.active {
		c.releaseAll()
		c.prevDx = 0
		c.prevDy = 0
		c.accumDx.Swap(0)
		c.accumDy.Swap(0)
		// 释放所有鼠标按键
		c.mu.Lock()
		for btn := range c.mouseButtons {
			KeyUp(c.mouseBtnKeyCode(btn))
			delete(c.mouseButtons, btn)
			delete(c.mouseBtnSince, btn)
		}
		c.mu.Unlock()
	}
	if c.active {
		HideCursor()
		fmt.Println("\n✅ 捕获已开启")
	} else {
		ShowCursor()
		fmt.Println("\n❌ 捕获已关闭")
	}
}

// HandleMouseButton 处理鼠标按键事件
func (c *Capture) HandleMouseButton(button int, down bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.muActive.Lock()
	active := c.active
	c.muActive.Unlock()

	if !active {
		return
	}

	var keyCode uint16
	switch button {
	case 1: // 左键
		keyCode = c.cfg.MouseLeftButton
	case 2: // 右键
		keyCode = c.cfg.MouseRightButton
	case 4: // 后退键 (XButton1)
		keyCode = c.cfg.MouseBackButton
	case 5: // 前进键 (XButton2)
		keyCode = c.cfg.MouseForwardBtn
	default:
		return
	}

	if keyCode == 0 {
		return
	}

	now := time.Now()
	if down {
		if !c.mouseButtons[button] {
			KeyDown(keyCode)
			c.mouseButtons[button] = true
			c.mouseBtnSince[button] = now
		}
	} else {
		if c.mouseButtons[button] {
			// 最小保持时间防抖
			if since, ok := c.mouseBtnSince[button]; ok {
				if now.Sub(since) < MinKeyHoldMs*time.Millisecond {
					return // 还没到最小保持时间，忽略释放
				}
			}
			KeyUp(keyCode)
			delete(c.mouseButtons, button)
			delete(c.mouseBtnSince, button)
		}
	}
}

func (c *Capture) mouseBtnKeyCode(button int) uint16 {
	switch button {
	case 1:
		return c.cfg.MouseLeftButton
	case 2:
		return c.cfg.MouseRightButton
	case 4:
		return c.cfg.MouseBackButton
	case 5:
		return c.cfg.MouseForwardBtn
	}
	return 0
}

func (c *Capture) PrintStatus() {
	c.muActive.Lock()
	active := c.active
	dir := c.dirName
	c.muActive.Unlock()

	status := "OFF"
	if active {
		status = "ON"
	}
	fmt.Printf("\r[%s] %s          ", status, dir)
}

func abs64(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

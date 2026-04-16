package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"
)

// macOS 虚拟键码映射表
var keyNameToCode = map[string]uint16{
	// 方向键
	"up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
	// 字母键
	"a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
	"f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
	"k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
	"p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
	"u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
	// 数字键
	"0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
	"5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
	// 功能键
	"enter": 0x24, "return": 0x24, "space": 0x31, "tab": 0x30,
	"esc": 0x35, "escape": 0x35, "delete": 0x33, "backspace": 0x33,
	// 修饰键
	"shift": 0x38, "ctrl": 0x3B, "control": 0x3B,
	"alt": 0x3A, "option": 0x3A, "cmd": 0x37, "command": 0x37,
}

type Config struct {
	MouseUp          uint16
	MouseDown        uint16
	MouseLeft        uint16
	MouseRight       uint16
	MouseLeftButton  uint16
	MouseRightButton uint16
	MouseBackButton  uint16
	MouseForwardBtn  uint16
	TickInterval     time.Duration // 采样间隔（由 mouse_sampling_rate 计算）
	CoastDuration    time.Duration // 惯性滑行时间
	NoiseThreshold   float64       // 噪声过滤阈值（smoothed delta 低于此值视为停止）
	KeepMove         bool          // 停下鼠标后是否保持移动方向
}

func defaultConfig() *Config {
	return &Config{
		MouseUp:          0x7E,
		MouseDown:        0x7D,
		MouseLeft:        0x7B,
		MouseRight:       0x7C,
		MouseLeftButton:  0x06, // z
		MouseRightButton: 0x07, // x
		MouseBackButton:  0x09, // v
		MouseForwardBtn:  0x24, // enter
		TickInterval:    time.Millisecond,
		CoastDuration:   80 * time.Millisecond,
		NoiseThreshold:  0,
	}
}

func LoadConfig(path string) (*Config, error) {
	cfg := defaultConfig()

	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			log.Printf("[CONFIG] %s 不存在，使用默认配置", path)
			return cfg, nil
		}
		return nil, fmt.Errorf("打开配置文件失败: %w", err)
	}
	defer f.Close()

	// 简单的 YAML flat key-value 解析（无需第三方库）
	mapping := map[string]*uint16{
		"mouse_up":          &cfg.MouseUp,
		"mouse_down":        &cfg.MouseDown,
		"mouse_left":        &cfg.MouseLeft,
		"mouse_right":       &cfg.MouseRight,
		"mouse_button_1":    &cfg.MouseLeftButton,  // 左键
		"mouse_button_2":    &cfg.MouseRightButton, // 右键
		"mouse_button_4":    &cfg.MouseBackButton,  // 侧键后退
		"mouse_button_5":    &cfg.MouseForwardBtn,  // 侧键前进
	}

	scanner := bufio.NewScanner(f)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		// 去掉行内注释
		if idx := strings.Index(val, "#"); idx >= 0 {
			val = strings.TrimSpace(val[:idx])
		}

		// 采样率配置
		if key == "mouse_sampling_rate" {
			if n, err := strconv.Atoi(val); err == nil && n > 0 {
				cfg.TickInterval = time.Second / time.Duration(n)
				log.Printf("[CONFIG] %s → %dHz (%v)", key, n, cfg.TickInterval)
			} else {
				log.Printf("[CONFIG] 无效的 %s: %s", key, val)
			}
			continue
		}

		if key == "move_inertia_time" {
			if f, err := strconv.ParseFloat(val, 64); err == nil && f >= 0 {
				cfg.CoastDuration = time.Duration(f * float64(time.Second))
				log.Printf("[CONFIG] %s → %v", key, cfg.CoastDuration)
			} else {
				log.Printf("[CONFIG] 无效的 %s: %s", key, val)
			}
			continue
		}

		if key == "mouse_reduces_noise" {
			if f, err := strconv.ParseFloat(val, 64); err == nil && f > 0 {
				cfg.NoiseThreshold = f
				log.Printf("[CONFIG] %s → %.2f", key, f)
			} else {
				log.Printf("[CONFIG] 无效的 %s: %s", key, val)
			}
			continue
		}

		if key == "keep_move" {
			if b, err := strconv.ParseBool(val); err == nil {
				cfg.KeepMove = b
				log.Printf("[CONFIG] %s → %v", key, b)
			} else {
				log.Printf("[CONFIG] 无效的 %s: %s", key, val)
			}
			continue
		}

		ptr, ok := mapping[key]
		if !ok {
			log.Printf("[CONFIG] 忽略未知配置项: %s (第 %d 行)", key, lineNo)
			continue
		}

		code, ok := keyNameToCode[strings.ToLower(val)]
		if !ok {
			log.Printf("[CONFIG] 未知按键名: %s (第 %d 行，配置项: %s)", val, lineNo, key)
			continue
		}

		*ptr = code
		log.Printf("[CONFIG] %s → %s (0x%02X)", key, val, code)
	}

	return cfg, scanner.Err()
}

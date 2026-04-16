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

// 键码映射表定义在 keys_darwin.go / keys_windows.go（按平台）

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
		MouseUp:          keyNameToCode["up"],
		MouseDown:        keyNameToCode["down"],
		MouseLeft:        keyNameToCode["left"],
		MouseRight:       keyNameToCode["right"],
		MouseLeftButton:  keyNameToCode["z"],
		MouseRightButton: keyNameToCode["x"],
		MouseBackButton:  keyNameToCode["v"],
		MouseForwardBtn:  keyNameToCode["enter"],
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

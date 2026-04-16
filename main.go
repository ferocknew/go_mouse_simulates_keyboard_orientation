package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	fmt.Println("🎮 VirtualGamepad v0.1.0")
	fmt.Println("Ctrl+ESC  切换捕获")
	fmt.Println("Ctrl+C    退出")
	fmt.Println("──────────────────────")

	// 检查辅助功能权限
	if !CheckAccessibility() {
		log.Println("[ERROR] 未获得辅助功能权限！")
		log.Println("[ERROR] 请前往：系统设置 > 隐私与安全性 > 辅助功能")
		log.Println("[ERROR] 添加终端应用或 virtualgamepad 二进制文件")
		fmt.Println()
		fmt.Println("按 Enter 继续尝试...")
		fmt.Scanln()
	} else {
		log.Println("[OK] 辅助功能权限已授予")
	}

	cap := NewCapture()
	done := make(chan struct{})

	errCh := make(chan error, 1)
	go func() {
		if err := StartEventTap(cap, done); err != nil {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		os.Exit(1)
	case <-time.After(500 * time.Millisecond):
		log.Println("[OK] 程序已就绪，移动鼠标或按 Ctrl+ESC")
	}

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-sigChan:
			fmt.Println("\n正在退出...")
			close(done)
			time.Sleep(100 * time.Millisecond)
			return
		case <-ticker.C:
			cap.PrintStatus()
		}
	}
}

package main

import (
	"fmt"
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

	cap := NewCapture()
	done := make(chan struct{})

	errCh := make(chan error, 1)
	go func() {
		if err := StartEventTap(cap, done); err != nil {
			errCh <- err
		}
	}()

	// 检查启动错误
	select {
	case err := <-errCh:
		fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		os.Exit(1)
	case <-time.After(200 * time.Millisecond):
		// event tap 启动成功
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
			return
		case <-ticker.C:
			cap.PrintStatus()
		}
	}
}

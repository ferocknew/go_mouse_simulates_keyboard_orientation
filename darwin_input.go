package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework CoreGraphics -framework CoreFoundation -framework ApplicationServices

#include "darwin.h"
*/
import "C"

import (
	"fmt"
	"log"
	"os"
	"runtime"
	"unsafe"
)

var captureRef *Capture

func CheckAccessibility() bool {
	return C.checkAccessibility() != 0
}

func KeyDown(keyCode uint16) {
	C.sendKeyDown(C.CGKeyCode(keyCode))
}

func KeyUp(keyCode uint16) {
	C.sendKeyUp(C.CGKeyCode(keyCode))
}

//export eventTapCallback
func eventTapCallback(proxy C.CGEventTapProxy, eventType C.CGEventType, event C.CGEventRef, userInfo unsafe.Pointer) C.CGEventRef {
	if captureRef == nil {
		return event
	}

	switch eventType {
	// 鼠标移动
	case C.kCGEventMouseMoved, C.kCGEventLeftMouseDragged:
		dx := C.CGEventGetIntegerValueField(event, C.kCGMouseEventDeltaX)
		dy := C.CGEventGetIntegerValueField(event, C.kCGMouseEventDeltaY)
		captureRef.UpdateMouseDelta(int64(dx), int64(dy))

	// 鼠标左键
	case C.kCGEventLeftMouseDown:
		captureRef.HandleMouseButton(0, true)
	case C.kCGEventLeftMouseUp:
		captureRef.HandleMouseButton(0, false)

	// 鼠标右键
	case C.kCGEventRightMouseDown:
		captureRef.HandleMouseButton(1, true)
	case C.kCGEventRightMouseUp:
		captureRef.HandleMouseButton(1, false)

	// 鼠标其他按键（侧键）
	case C.kCGEventOtherMouseDown:
		btn := int(C.CGEventGetIntegerValueField(event, C.kCGMouseEventButtonNumber))
		captureRef.HandleMouseButton(btn, true)
	case C.kCGEventOtherMouseUp:
		btn := int(C.CGEventGetIntegerValueField(event, C.kCGMouseEventButtonNumber))
		captureRef.HandleMouseButton(btn, false)

	// 键盘
	case C.kCGEventKeyDown:
		keycode := C.CGEventGetIntegerValueField(event, C.kCGKeyboardEventKeycode)
		flags := C.CGEventGetFlags(event)
		// Ctrl+ESC (keycode 0x35) 切换捕获状态
		if keycode == 0x35 && (flags&C.kCGEventFlagMaskControl) != 0 {
			log.Printf("[HOTKEY] Ctrl+ESC 检测到，切换捕获状态")
			captureRef.Toggle()
		}

	case C.kCGEventTapDisabledByTimeout:
		log.Printf("[WARN] EventTap 因超时被禁用，重新启用")
		C.CGEventTapEnable(C.CFMachPortRef(unsafe.Pointer(nil)), C._Bool(true))

	case C.kCGEventTapDisabledByUserInput:
		log.Printf("[WARN] EventTap 因用户输入被禁用")
	}

	return event
}

func StartEventTap(cap *Capture, done chan struct{}) error {
	captureRef = cap
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	log.Println("[INIT] 正在启动事件监听...")

	if C.createEventTap() == 0 {
		return fmt.Errorf("无法创建事件监听 - 请在「系统设置 > 隐私与安全性 > 辅助功能」中授权")
	}

	log.Println("[INIT] 事件监听已启动，进入主循环")

	go func() {
		<-done
		log.Println("[EXIT] 收到退出信号，停止事件监听")
		C.stopEventTap()
		C.CFRunLoopStop(C.CFRunLoopGetCurrent())
	}()

	C.CFRunLoopRun()
	return nil
}

func init() {
	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ltime | log.Lmicroseconds)
}

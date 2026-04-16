package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework CoreGraphics -framework CoreFoundation -framework ApplicationServices -framework IOKit

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

func HideCursor() {
	C.hideCursor()
}

func ShowCursor() {
	C.showCursor()
}

// ===== CGEventTap 回调（鼠标移动 + 键盘热键）=====

//export eventTapCallback
func eventTapCallback(proxy C.CGEventTapProxy, eventType C.CGEventType, event C.CGEventRef, userInfo unsafe.Pointer) C.CGEventRef {
	if captureRef == nil {
		return event
	}

	switch eventType {
	case C.kCGEventMouseMoved, C.kCGEventLeftMouseDragged:
		dx := C.CGEventGetIntegerValueField(event, C.kCGMouseEventDeltaX)
		dy := C.CGEventGetIntegerValueField(event, C.kCGMouseEventDeltaY)
		captureRef.AddDelta(int64(dx), int64(dy))

		// 捕获激活时吞掉鼠标移动事件
		captureRef.muActive.Lock()
		active := captureRef.active
		captureRef.muActive.Unlock()
		if active {
				return C.CGEventRef(unsafe.Pointer(nil))
			}

	case C.kCGEventLeftMouseDown, C.kCGEventLeftMouseUp,
		C.kCGEventRightMouseDown, C.kCGEventRightMouseUp,
		C.kCGEventOtherMouseDown, C.kCGEventOtherMouseUp:
		// 捕获激活时吞掉鼠标点击事件，防止切换到其他应用
		captureRef.muActive.Lock()
		active := captureRef.active
		captureRef.muActive.Unlock()
		if active {
			return C.CGEventRef(unsafe.Pointer(nil))
		}

	case C.kCGEventKeyDown:
		keycode := C.CGEventGetIntegerValueField(event, C.kCGKeyboardEventKeycode)
		flags := C.CGEventGetFlags(event)
		if keycode == 0x35 && (flags&C.kCGEventFlagMaskControl) != 0 {
			log.Printf("[HOTKEY] Ctrl+ESC 检测到，切换捕获状态")
			captureRef.Toggle()
			return C.CGEventRef(unsafe.Pointer(nil)) // 吞掉 Ctrl+ESC
		}

	case C.kCGEventTapDisabledByTimeout:
		log.Printf("[WARN] EventTap 因超时被禁用，重新启用")
		C.reenableEventTap()

	case C.kCGEventTapDisabledByUserInput:
		log.Printf("[WARN] EventTap 因用户输入被禁用")
	}

	return event
}

// ===== IOHIDManager 回调（鼠标按键，包括侧键）=====
// usage: 1=左键, 2=右键, 3=中键, 4=后退, 5=前进

//export hidButtonCallback
func hidButtonCallback(usage C.int, pressed C.int) {
	if captureRef == nil {
		return
	}

	btn := int(usage)
	down := int(pressed) == 1
	log.Printf("[HID] Button usage=%d pressed=%d", btn, int(pressed))
	captureRef.HandleMouseButton(btn, down)
}

// ===== 启动/停止 =====

func StartEventTap(cap *Capture, done chan struct{}) error {
	captureRef = cap
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	log.Println("[INIT] 正在启动事件监听...")

	// 启动 IOHIDManager（鼠标按键）
	if C.startHIDManager() == 0 {
		log.Println("[WARN] IOHIDManager 启动失败，鼠标按键可能不可用")
	}

	// 启动 CGEventTap（鼠标移动 + 键盘热键）
	if C.createEventTap() == 0 {
		return fmt.Errorf("无法创建事件监听 - 请在「系统设置 > 隐私与安全性 > 辅助功能」中授权")
	}

	log.Println("[INIT] 事件监听已启动，进入主循环")

	go func() {
		<-done
		log.Println("[EXIT] 收到退出信号，停止事件监听")
		C.stopEventTap()
		C.stopHIDManager()
		C.CFRunLoopStop(C.CFRunLoopGetCurrent())
	}()

	C.CFRunLoopRun()
	return nil
}

func init() {
	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ltime | log.Lmicroseconds)
}

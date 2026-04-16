package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework CoreGraphics -framework CoreFoundation

#include "darwin.h"
*/
import "C"

import (
	"fmt"
	"runtime"
	"unsafe"
)

var captureRef *Capture

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
	case C.kCGEventMouseMoved, C.kCGEventLeftMouseDragged:
		dx := C.CGEventGetIntegerValueField(event, C.kCGMouseEventDeltaX)
		dy := C.CGEventGetIntegerValueField(event, C.kCGMouseEventDeltaY)
		captureRef.UpdateMouseDelta(int64(dx), int64(dy))

	case C.kCGEventKeyDown:
		keycode := C.CGEventGetIntegerValueField(event, C.kCGKeyboardEventKeycode)
		flags := C.CGEventGetFlags(event)
		// Ctrl+ESC (keycode 0x35) 切换捕获状态
		if keycode == 0x35 && (flags&C.kCGEventFlagMaskControl) != 0 {
			captureRef.Toggle()
		}
	}

	return event
}

func StartEventTap(cap *Capture, done chan struct{}) error {
	captureRef = cap
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	if C.createEventTap() == 0 {
		return fmt.Errorf("无法创建事件监听 - 请在「系统设置 > 隐私与安全性 > 辅助功能」中授权")
	}

	go func() {
		<-done
		C.stopEventTap()
		C.CFRunLoopStop(C.CFRunLoopGetCurrent())
	}()

	C.CFRunLoopRun()
	return nil
}

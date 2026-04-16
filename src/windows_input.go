//go:build windows

package main

import (
	"fmt"
	"log"
	"os"
	"runtime"
	"syscall"
	"unsafe"
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")

	procSetWindowsHookEx    = user32.NewProc("SetWindowsHookExW")
	procCallNextHookEx      = user32.NewProc("CallNextHookEx")
	procUnhookWindowsHookEx = user32.NewProc("UnhookWindowsHookEx")
	procGetMessage          = user32.NewProc("GetMessageW")
	procPostThreadMessage   = user32.NewProc("PostThreadMessageW")
	procSendInput           = user32.NewProc("SendInput")
	procShowCursor          = user32.NewProc("ShowCursor")
	procGetCursorPos        = user32.NewProc("GetCursorPos")
	procGetAsyncKeyState    = user32.NewProc("GetAsyncKeyState")
	procGetCurrentThreadId  = kernel32.NewProc("GetCurrentThreadId")
)

const (
	WH_MOUSE_LL    = 14
	WH_KEYBOARD_LL = 13

	WM_MOUSEMOVE   = 0x0200
	WM_LBUTTONDOWN = 0x0201
	WM_LBUTTONUP   = 0x0202
	WM_RBUTTONDOWN = 0x0203
	WM_RBUTTONUP   = 0x0204
	WM_XBUTTONDOWN = 0x020B
	WM_XBUTTONUP   = 0x020C

	WM_KEYDOWN    = 0x0100
	WM_SYSKEYDOWN = 0x0104

	WM_QUIT = 0x0012

	VK_ESCAPE = 0x1B
	VK_CONTROL = 0x11

	INPUT_KEYBOARD  = 1
	KEYEVENTF_KEYUP = 0x0002
)

type tagPOINT struct {
	X, Y int32
}

type tagMSG struct {
	HWnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      tagPOINT
}

type tagMSLLHOOKSTRUCT struct {
	Pt          tagPOINT
	MouseData   uint32
	Flags       uint32
	Time        uint32
	DwExtraInfo uintptr
}

type tagKBDLLHOOKSTRUCT struct {
	VkCode      uint32
	ScanCode    uint32
	Flags       uint32
	Time        uint32
	DwExtraInfo uintptr
}

type tagKEYBDINPUT struct {
	WVk         uint16
	WScan       uint16
	DwFlags     uint32
	Time        uint32
	DwExtraInfo uintptr
}

type tagINPUT struct {
	Type uint32
	Pad  [4]byte // 对齐
	Ki   tagKEYBDINPUT
}

var (
	captureRef   *Capture
	mouseHook    uintptr
	keyboardHook uintptr
	hookThreadID uint32
)

func CheckAccessibility() bool {
	return true // Windows 不需要辅助功能权限
}

func KeyDown(keyCode uint16) {
	input := tagINPUT{
		Type: INPUT_KEYBOARD,
		Ki: tagKEYBDINPUT{
			WVk: keyCode,
		},
	}
	procSendInput.Call(1, uintptr(unsafe.Pointer(&input)), unsafe.Sizeof(input))
}

func KeyUp(keyCode uint16) {
	input := tagINPUT{
		Type: INPUT_KEYBOARD,
		Ki: tagKEYBDINPUT{
			WVk:     keyCode,
			DwFlags: KEYEVENTF_KEYUP,
		},
	}
	procSendInput.Call(1, uintptr(unsafe.Pointer(&input)), unsafe.Sizeof(input))
}

func HideCursor() {
	procShowCursor.Call(0)
}

func ShowCursor() {
	// ShowCursor 是计数器，多次调用确保显示
	for i := 0; i < 10; i++ {
		procShowCursor.Call(1)
	}
}

func lowLevelMouseProc(nCode int32, wParam uintptr, lParam uintptr) uintptr {
	if nCode >= 0 && captureRef != nil {
		info := (*tagMSLLHOOKSTRUCT)(unsafe.Pointer(lParam))

		captureRef.muActive.Lock()
		active := captureRef.active
		captureRef.muActive.Unlock()

		switch wParam {
		case WM_MOUSEMOVE:
			if active {
				var curPos tagPOINT
				procGetCursorPos.Call(uintptr(unsafe.Pointer(&curPos)))
				dx := int64(info.Pt.X - curPos.X)
				dy := int64(info.Pt.Y - curPos.Y)
				if dx != 0 || dy != 0 {
					captureRef.AddDelta(dx, dy)
				}
				return 1 // 阻止事件
			}

		case WM_LBUTTONDOWN:
			if active {
				captureRef.HandleMouseButton(1, true)
				return 1
			}
		case WM_LBUTTONUP:
			if active {
				captureRef.HandleMouseButton(1, false)
				return 1
			}
		case WM_RBUTTONDOWN:
			if active {
				captureRef.HandleMouseButton(2, true)
				return 1
			}
		case WM_RBUTTONUP:
			if active {
				captureRef.HandleMouseButton(2, false)
				return 1
			}
		case WM_XBUTTONDOWN:
			if active {
				xbtn := int(info.MouseData >> 16)
				btn := 0
				if xbtn == 1 {
					btn = 4
				}
				if xbtn == 2 {
					btn = 5
				}
				if btn != 0 {
					captureRef.HandleMouseButton(btn, true)
				}
				return 1
			}
		case WM_XBUTTONUP:
			if active {
				xbtn := int(info.MouseData >> 16)
				btn := 0
				if xbtn == 1 {
					btn = 4
				}
				if xbtn == 2 {
					btn = 5
				}
				if btn != 0 {
					captureRef.HandleMouseButton(btn, false)
				}
				return 1
			}
		}
	}

	ret, _, _ := procCallNextHookEx.Call(0, uintptr(nCode), wParam, lParam)
	return ret
}

func lowLevelKeyboardProc(nCode int32, wParam uintptr, lParam uintptr) uintptr {
	if nCode >= 0 && captureRef != nil {
		info := (*tagKBDLLHOOKSTRUCT)(unsafe.Pointer(lParam))

		if wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN {
			if info.VkCode == VK_ESCAPE {
				ctrlState, _, _ := procGetAsyncKeyState.Call(VK_CONTROL)
				if ctrlState&0x8000 != 0 {
					log.Printf("[HOTKEY] Ctrl+ESC 检测到，切换捕获状态")
					captureRef.Toggle()
					return 1
				}
			}
		}
	}

	ret, _, _ := procCallNextHookEx.Call(0, uintptr(nCode), wParam, lParam)
	return ret
}

func StartEventTap(cap *Capture, done chan struct{}) error {
	captureRef = cap
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	log.Println("[INIT] 正在启动事件监听...")

	// 保存线程 ID，用于退出时发送 WM_QUIT
	tid, _, _ := procGetCurrentThreadId.Call()
	hookThreadID = uint32(tid)

	// 安装低级鼠标钩子
	mouseCB := syscall.NewCallback(lowLevelMouseProc)
	hMouse, _, _ := procSetWindowsHookEx.Call(
		WH_MOUSE_LL,
		mouseCB,
		0, 0,
	)
	if hMouse == 0 {
		return fmt.Errorf("无法安装鼠标钩子")
	}
	mouseHook = hMouse

	// 安装低级键盘钩子
	kbdCB := syscall.NewCallback(lowLevelKeyboardProc)
	hKbd, _, _ := procSetWindowsHookEx.Call(
		WH_KEYBOARD_LL,
		kbdCB,
		0, 0,
	)
	if hKbd == 0 {
		procUnhookWindowsHookEx.Call(mouseHook)
		return fmt.Errorf("无法安装键盘钩子")
	}
	keyboardHook = hKbd

	log.Println("[INIT] 事件钩子已安装，进入消息循环")

	go func() {
		<-done
		log.Println("[EXIT] 收到退出信号，停止事件监听")
		procPostThreadMessage.Call(uintptr(hookThreadID), WM_QUIT, 0, 0)
	}()

	// 消息循环
	var msg tagMSG
	for {
		ret, _, _ := procGetMessage.Call(
			uintptr(unsafe.Pointer(&msg)),
			0, 0, 0,
		)
		if ret == 0 || int32(ret) == -1 {
			break
		}
	}

	procUnhookWindowsHookEx.Call(keyboardHook)
	procUnhookWindowsHookEx.Call(mouseHook)

	return nil
}

func init() {
	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ltime | log.Lmicroseconds)
}

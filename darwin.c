#include "darwin.h"
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// Go 回调函数的声明
extern CGEventRef eventTapCallback(CGEventTapProxy proxy,
    CGEventType type, CGEventRef event, void *userInfo);
extern void hidButtonCallback(int usage, int pressed);

static CFRunLoopSourceRef runLoopSource = NULL;
static CFMachPortRef eventTapPort = NULL;
static IOHIDManagerRef hidManager = NULL;

void sendKeyDown(CGKeyCode key) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, key, true);
    if (event) {
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
    }
}

void sendKeyUp(CGKeyCode key) {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, key, false);
    if (event) {
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
    }
}

int checkAccessibility(void) {
    return AXIsProcessTrusted();
}

// ===== CGEventTap（鼠标移动 + 键盘热键）=====

int createEventTap(void) {
    CGEventMask eventMask =
        CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventLeftMouseDragged) |
        CGEventMaskBit(kCGEventLeftMouseDown) |
        CGEventMaskBit(kCGEventLeftMouseUp) |
        CGEventMaskBit(kCGEventRightMouseDown) |
        CGEventMaskBit(kCGEventRightMouseUp) |
        CGEventMaskBit(kCGEventOtherMouseDown) |
        CGEventMaskBit(kCGEventOtherMouseUp) |
        CGEventMaskBit(kCGEventKeyDown);

    fprintf(stderr, "[DEBUG] 正在创建 EventTap...\n");

    eventTapPort = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        eventMask,
        (CGEventTapCallBack)eventTapCallback,
        NULL
    );

    if (!eventTapPort) {
        fprintf(stderr, "[ERROR] CGEventTapCreate 返回 NULL\n");
        return 0;
    }

    if (!CGEventTapIsEnabled(eventTapPort)) {
        CGEventTapEnable(eventTapPort, true);
        if (!CGEventTapIsEnabled(eventTapPort)) {
            fprintf(stderr, "[ERROR] 无法启用 EventTap\n");
            return 0;
        }
    }

    fprintf(stderr, "[DEBUG] EventTap 已启用\n");

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault, eventTapPort, 0);
    runLoopSource = source;
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);

    return 1;
}

void stopEventTap(void) {
    if (eventTapPort) {
        CGEventTapEnable(eventTapPort, false);
        if (runLoopSource) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
            CFRelease(runLoopSource);
            runLoopSource = NULL;
        }
        CFRelease(eventTapPort);
        eventTapPort = NULL;
    }
}

// ===== IOHIDManager（鼠标按键，包括侧键）=====

static void hidInputCallback(void* context,
    IOReturn result, void* sender, IOHIDValueRef value) {

    IOHIDElementRef elem = IOHIDValueGetElement(value);
    uint32_t usagePage = IOHIDElementGetUsagePage(elem);
    uint32_t usage = IOHIDElementGetUsage(elem);
    int pressed = IOHIDValueGetIntegerValue(value);

    // Button Page (0x09): usage 1=左键, 2=右键, 3=中键, 4=后退, 5=前进
    if (usagePage == 0x09 && pressed >= 0) {
        hidButtonCallback((int)usage, pressed);
    }
}

int startHIDManager(void) {
    fprintf(stderr, "[DEBUG] 正在启动 IOHIDManager...\n");

    hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!hidManager) {
        fprintf(stderr, "[ERROR] IOHIDManagerCreate 失败\n");
        return 0;
    }

    // 匹配所有 HID 设备
    IOHIDManagerSetDeviceMatching(hidManager, NULL);

    IOHIDManagerRegisterInputValueCallback(hidManager, hidInputCallback, NULL);
    IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    IOReturn ret = IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "[ERROR] IOHIDManagerOpen 失败: 0x%X\n", ret);
        return 0;
    }

    fprintf(stderr, "[DEBUG] IOHIDManager 已启动\n");
    return 1;
}

void stopHIDManager(void) {
    if (hidManager) {
        IOHIDManagerClose(hidManager, kIOHIDOptionsTypeNone);
        CFRelease(hidManager);
        hidManager = NULL;
    }
}

void hideCursor(void) {
    CGDisplayHideCursor(CGMainDisplayID());
}

void showCursor(void) {
    CGDisplayShowCursor(CGMainDisplayID());
}

void reenableEventTap(void) {
    if (eventTapPort) {
        CGEventTapEnable(eventTapPort, true);
    }
}

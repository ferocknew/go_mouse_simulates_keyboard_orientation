#include "darwin.h"
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// Go 回调函数的声明
extern CGEventRef eventTapCallback(CGEventTapProxy proxy,
    CGEventType type, CGEventRef event, void *userInfo);

static CFRunLoopSourceRef runLoopSource = NULL;
static CFMachPortRef eventTapPort = NULL;

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

int createEventTap(void) {
    // 鼠标移动 + 鼠标按下/释放（左、右、其他）+ 键盘按下
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
        kCGEventTapOptionListenOnly,
        eventMask,
        (CGEventTapCallBack)eventTapCallback,
        NULL
    );

    if (!eventTapPort) {
        fprintf(stderr, "[ERROR] CGEventTapCreate 返回 NULL\n");
        return 0;
    }

    fprintf(stderr, "[DEBUG] EventTap 创建成功, 检查是否启用...\n");

    if (!CGEventTapIsEnabled(eventTapPort)) {
        fprintf(stderr, "[WARN] EventTap 已创建但未启用，尝试启用...\n");
        CGEventTapEnable(eventTapPort, true);
        if (!CGEventTapIsEnabled(eventTapPort)) {
            fprintf(stderr, "[ERROR] 无法启用 EventTap，可能缺少辅助功能权限\n");
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

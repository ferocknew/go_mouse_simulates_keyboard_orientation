#include "darwin.h"
#include <CoreGraphics/CoreGraphics.h>

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

int createEventTap(void) {
    CGEventMask eventMask =
        CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventLeftMouseDragged) |
        CGEventMaskBit(kCGEventKeyDown);

    eventTapPort = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionListenOnly,
        eventMask,
        (CGEventTapCallBack)eventTapCallback,
        NULL
    );

    if (!eventTapPort) {
        return 0;
    }

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(
        kCFAllocatorDefault, eventTapPort, 0);
    runLoopSource = source;

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTapPort, true);
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

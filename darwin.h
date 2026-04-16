#ifndef DARWIN_H
#define DARWIN_H

#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>
#include <IOKit/hid/IOHIDManager.h>

// 键盘输出
void sendKeyDown(CGKeyCode key);
void sendKeyUp(CGKeyCode key);

// CGEventTap（鼠标移动 + 键盘热键）
int createEventTap(void);
void stopEventTap(void);

// IOHIDManager（鼠标按键，包括侧键）
int startHIDManager(void);
void stopHIDManager(void);

// 权限检查
int checkAccessibility(void);

#endif

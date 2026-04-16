#ifndef DARWIN_H
#define DARWIN_H

#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>

// 键盘输出
void sendKeyDown(CGKeyCode key);
void sendKeyUp(CGKeyCode key);

// 事件监听
int createEventTap(void);
void stopEventTap(void);

// 权限检查
int checkAccessibility(void);

#endif

//
//  mouse_interceptor.swift
//  VirtualGamepadDemo
//

import Foundation
import CoreGraphics
import ApplicationServices

nonisolated final class MouseInterceptor: @unchecked Sendable {
    var onMouseMove: (@Sendable (Int, Int) -> Void)?
    var onLeftClick: (@Sendable (Bool) -> Void)?
    var onRightClick: (@Sendable (Bool) -> Void)?
    var onMiddleClick: (@Sendable (Bool) -> Void)?
    var onOtherButton: (@Sendable (Int32, Bool) -> Void)?  // (buttonNumber, pressed)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoopThread: Thread?
    private var _isActive = true

    var isActive: Bool {
        return _isActive
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else {
            print("Accessibility permission not granted")
            return false
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                MouseInterceptor.eventCallback(proxy: proxy, type: type, event: event, refcon: refcon)
            },
            userInfo: userInfo
        ) else {
            print("Failed to create CGEventTap")
            return false
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        runLoopThread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        runLoopThread?.name = "MouseEventTap"
        runLoopThread?.start()

        print("Mouse interceptor started")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let thread = runLoopThread {
            let cfRunLoop = CFRunLoopGetMain()
            CFRunLoopRemoveSource(cfRunLoop, source, .commonModes)
            CFRunLoopStop(cfRunLoop)
        }
        eventTap = nil
        runLoopSource = nil
        runLoopThread = nil
        print("Mouse interceptor stopped")
    }

    func setActive(_ active: Bool) {
        _isActive = active
        CGAssociateMouseAndMouseCursorPosition(active ? 0 : 1)
    }

    private static func eventCallback(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent,
        refcon: UnsafeMutableRawPointer?
    ) -> Unmanaged<CGEvent>? {
        guard let refcon = refcon else { return Unmanaged.passRetained(event) }
        let interceptor = Unmanaged<MouseInterceptor>.fromOpaque(refcon).takeUnretainedValue()

        if !interceptor.isActive {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let dx = Int(event.getIntegerValueField(.mouseEventDeltaX))
            let dy = Int(event.getIntegerValueField(.mouseEventDeltaY))
            interceptor.onMouseMove?(dx, dy)

        case .leftMouseDown:
            interceptor.onLeftClick?(true)
        case .leftMouseUp:
            interceptor.onLeftClick?(false)

        case .rightMouseDown:
            interceptor.onRightClick?(true)
        case .rightMouseUp:
            interceptor.onRightClick?(false)

        case .otherMouseDown:
            let btnNum = event.getIntegerValueField(.mouseEventButtonNumber)
            if btnNum == 2 {
                interceptor.onMiddleClick?(true)
            } else {
                interceptor.onOtherButton?(Int32(btnNum), true)
            }
        case .otherMouseUp:
            let btnNum = event.getIntegerValueField(.mouseEventButtonNumber)
            if btnNum == 2 {
                interceptor.onMiddleClick?(false)
            } else {
                interceptor.onOtherButton?(Int32(btnNum), false)
            }

        default:
            break
        }

        return nil
    }

    deinit {
        stop()
    }
}

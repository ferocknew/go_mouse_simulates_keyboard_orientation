//
//  gamepad_controller.swift
//  VirtualGamepadDemo
//

import Foundation
import SwiftUI
import ApplicationServices
import CoreGraphics

@MainActor
@Observable
final class GamepadController {
    var isActive: Bool = false
    var isConnected: Bool = false
    var accessibilityGranted: Bool = false
    var lastReport: GamepadReport = .zero
    var statusMessage: String = "正在初始化..."
    var sensitivity: Float = 1.0 {
        didSet { inputMapper.sensitivity = sensitivity }
    }

    private var hidDevice: VirtualHIDDevice?
    private var mouseInterceptor: MouseInterceptor?
    private var keyboardMonitor: KeyboardMonitor?
    private let inputMapper = InputMapper()
    private var reportTimer: DispatchSourceTimer?

    // Delta accumulator (accessed from CGEventTap thread - nonisolated)
    nonisolated(unsafe) private let accumulatorLock = NSLock()
    nonisolated(unsafe) private var _accumulatedDX: Int = 0
    nonisolated(unsafe) private var _accumulatedDY: Int = 0

    func setup() {
        checkAccessibility()

        if accessibilityGranted {
            startDevice()
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibility()
                if self?.accessibilityGranted == true && self?.isConnected == false {
                    self?.startDevice()
                }
            }
        }
    }

    private func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            let promptKey = Unmanaged.passUnretained(kAXTrustedCheckOptionPrompt.takeRetainedValue())
            let options = [promptKey.takeUnretainedValue() as NSString: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            statusMessage = "请授予辅助功能权限"
        }
    }

    private func startDevice() {
        hidDevice = VirtualHIDDevice()
        if hidDevice?.create() == true {
            isConnected = true
            statusMessage = "设备已连接，按 Ctrl+Esc 开始"
        } else {
            statusMessage = "虚拟设备创建失败"
        }
    }

    func toggleInterception() {
        if isActive {
            stopInterception()
        } else {
            startInterception()
        }
    }

    private func startInterception() {
        guard accessibilityGranted else {
            statusMessage = "需要辅助功能权限"
            return
        }

        let mapper = inputMapper
        let device = hidDevice

        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.onMouseMove = { [weak self] dx, dy in
            self?.accumulateDelta(dx, dy)
        }
        mouseInterceptor?.onLeftClick = { pressed in
            mapper.setButton(0, pressed: pressed)
        }
        mouseInterceptor?.onRightClick = { pressed in
            mapper.setButton(1, pressed: pressed)
        }
        mouseInterceptor?.onMiddleClick = { pressed in
            mapper.setButton(2, pressed: pressed)
        }
        mouseInterceptor?.onScroll = { delta in
            mapper.processScroll(delta)
        }

        guard mouseInterceptor?.start() == true else {
            statusMessage = "鼠标拦截启动失败"
            mouseInterceptor = nil
            return
        }

        mouseInterceptor?.setActive(true)

        keyboardMonitor = KeyboardMonitor()
        keyboardMonitor?.onToggleHotkey = { [weak self] in
            Task { @MainActor in self?.toggleInterception() }
        }
        keyboardMonitor?.start()

        startReportTimer()

        isActive = true
        statusMessage = "拦截中... (Ctrl+Esc 停止)"
    }

    private func stopInterception() {
        mouseInterceptor?.setActive(false)
        mouseInterceptor?.stop()
        mouseInterceptor = nil

        keyboardMonitor?.stop()
        keyboardMonitor = nil

        stopReportTimer()

        inputMapper.reset()
        lastReport = .zero
        hidDevice?.sendReport(.zero)

        isActive = false
        statusMessage = "已暂停 (Ctrl+Esc 开始)"
    }

    private func startReportTimer() {
        let mapper = inputMapper
        let device = hidDevice

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            let (dx, dy) = Self.consumeAccumulatedDelta(self: self)

            if dx != 0 || dy != 0 {
                mapper.processMouseDelta(dx, dy)
            }

            mapper.decayTick()
            let report = mapper.currentReport()

            device?.sendReport(report)

            Task { @MainActor [weak self] in
                self?.lastReport = report
            }
        }
        timer.resume()
        reportTimer = timer
    }

    private func stopReportTimer() {
        reportTimer?.cancel()
        reportTimer = nil
    }

    // Thread-safe delta accumulation (called from CGEventTap thread)
    nonisolated private func accumulateDelta(_ dx: Int, _ dy: Int) {
        accumulatorLock.lock()
        _accumulatedDX += dx
        _accumulatedDY += dy
        accumulatorLock.unlock()
    }

    private static func consumeAccumulatedDelta(self: GamepadController?) -> (dx: Int, dy: Int) {
        guard let self = self else { return (0, 0) }
        self.accumulatorLock.lock()
        let dx = self._accumulatedDX
        let dy = self._accumulatedDY
        self._accumulatedDX = 0
        self._accumulatedDY = 0
        self.accumulatorLock.unlock()
        return (dx, dy)
    }
}

//
//  gamepad_controller.swift
//  VirtualGamepadDemo
//

import Foundation
import SwiftUI
import ApplicationServices

@MainActor
@Observable
final class GamepadController {
    var isCaptured: Bool = false
    var accessibilityGranted: Bool = false
    var statusMessage: String = "正在初始化..."

    // 方向状态（用于 UI 显示）
    var isUp: Bool = false
    var isDown: Bool = false
    var isLeft: Bool = false
    var isRight: Bool = false
    var buttonA: Bool = false
    var buttonB: Bool = false
    var buttonC: Bool = false
    var buttonD: Bool = false

    // 灵敏度
    var sensitivity: Float = 3.0 {
        didSet { direction.threshold = sensitivity }
    }

    // 按钮键位配置
    var buttonAKeyName: String = "J"
    var buttonBKeyName: String = "K"
    var buttonCKeyName: String = "U"
    var buttonDKeyName: String = "I"
    var selectKeyName: String = "N"
    var startKeyName: String = "M"

    private var mouseInterceptor: MouseInterceptor?
    private var keyboardMonitor: KeyboardMonitor?
    private let keySim = KeySimulator()
    private let direction = DirectionState()
    private var reportTimer: DispatchSourceTimer?

    nonisolated(unsafe) private let accumulatorLock = NSLock()
    nonisolated(unsafe) private var _accumulatedDX: Int = 0
    nonisolated(unsafe) private var _accumulatedDY: Int = 0

    func setup() {
        checkAccessibility()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibility()
            }
        }
    }

    private func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            statusMessage = "请授予辅助功能权限"
        } else {
            statusMessage = "就绪 - 点击按钮捕获鼠标"
        }
    }

    func toggleCapture() {
        if isCaptured {
            stopCapture()
        } else {
            startCapture()
        }
    }

    private func startCapture() {
        guard accessibilityGranted else {
            statusMessage = "需要辅助功能权限"
            return
        }

        direction.reset()
        direction.threshold = sensitivity

        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.onMouseMove = { [weak self] dx, dy in
            self?.accumulateDelta(dx, dy)
        }
        mouseInterceptor?.onLeftClick = { [weak self] pressed in
            Task { @MainActor in self?.handleButtonA(pressed) }
        }
        mouseInterceptor?.onRightClick = { [weak self] pressed in
            Task { @MainActor in self?.handleButtonB(pressed) }
        }
        mouseInterceptor?.onMiddleClick = { [weak self] pressed in
            Task { @MainActor in self?.handleButtonC(pressed) }
        }
        mouseInterceptor?.onOtherButton = { [weak self] buttonNum, pressed in
            Task { @MainActor in self?.handleOtherButton(buttonNum, pressed) }
        }

        guard mouseInterceptor?.start() == true else {
            statusMessage = "鼠标拦截启动失败"
            mouseInterceptor = nil
            return
        }

        mouseInterceptor?.setActive(true)

        keyboardMonitor = KeyboardMonitor()
        keyboardMonitor?.onToggleHotkey = { [weak self] in
            Task { @MainActor in self?.toggleCapture() }
        }
        keyboardMonitor?.start()

        startReportTimer()

        isCaptured = true
        statusMessage = "捕获中... (Ctrl+Esc 释放)"
    }

    private func stopCapture() {
        mouseInterceptor?.setActive(false)
        mouseInterceptor?.stop()
        mouseInterceptor = nil

        keyboardMonitor?.stop()
        keyboardMonitor = nil

        stopReportTimer()

        keySim.releaseAll()
        direction.reset()
        resetUIState()

        isCaptured = false
        statusMessage = "已释放 - 点击按钮重新捕获"
    }

    // MARK: - Button handlers

    private func handleButtonA(_ pressed: Bool) {
        buttonA = pressed
        if pressed { keySim.pressKey(keySim.buttonAKeyCode) }
        else { keySim.releaseKey(keySim.buttonAKeyCode) }
    }

    private func handleButtonB(_ pressed: Bool) {
        buttonB = pressed
        if pressed { keySim.pressKey(keySim.buttonBKeyCode) }
        else { keySim.releaseKey(keySim.buttonBKeyCode) }
    }

    private func handleButtonC(_ pressed: Bool) {
        buttonC = pressed
        if pressed { keySim.pressKey(keySim.buttonCKeyCode) }
        else { keySim.releaseKey(keySim.buttonCKeyCode) }
    }

    private func handleOtherButton(_ buttonNum: Int32, _ pressed: Bool) {
        guard buttonNum >= 3 else { return }
        if buttonNum == 3 {
            buttonD = pressed
            if pressed { keySim.pressKey(keySim.buttonDKeyCode) }
            else { keySim.releaseKey(keySim.buttonDKeyCode) }
        }
    }

    private func resetUIState() {
        isUp = false; isDown = false; isLeft = false; isRight = false
        buttonA = false; buttonB = false; buttonC = false; buttonD = false
    }

    // MARK: - Report timer (125Hz)

    private func startReportTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            self?.reportTick()
        }
        timer.resume()
        reportTimer = timer
    }

    private func stopReportTimer() {
        reportTimer?.cancel()
        reportTimer = nil
    }

    nonisolated private func reportTick() {
        // 消费累积的鼠标 delta
        let (dx, dy) = consumeAccumulatedDelta()
        if dx != 0 || dy != 0 {
            direction.addDelta(dx, dy)
        }
        direction.decay()

        // 模拟方向键：D-pad (箭头) + X摇杆 (WASD) 同时输出
        let prevUp = direction.isUp
        let prevDown = direction.isDown
        let prevLeft = direction.isLeft
        let prevRight = direction.isRight

        // WASD (X摇杆)
        syncKey(keySim.keyCodeW, pressed: direction.isUp, wasPressed: prevUp)
        syncKey(keySim.keyCodeS, pressed: direction.isDown, wasPressed: prevDown)
        syncKey(keySim.keyCodeA, pressed: direction.isLeft, wasPressed: prevLeft)
        syncKey(keySim.keyCodeD, pressed: direction.isRight, wasPressed: prevRight)

        // Arrow keys (D-pad)
        syncKey(keySim.keyCodeUp, pressed: direction.isUp, wasPressed: prevUp)
        syncKey(keySim.keyCodeDown, pressed: direction.isDown, wasPressed: prevDown)
        syncKey(keySim.keyCodeLeft, pressed: direction.isLeft, wasPressed: prevLeft)
        syncKey(keySim.keyCodeRight, pressed: direction.isRight, wasPressed: prevRight)

        // 更新 UI
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isUp = self.direction.isUp
            self.isDown = self.direction.isDown
            self.isLeft = self.direction.isLeft
            self.isRight = self.direction.isRight
        }
    }

    nonisolated private func syncKey(_ keyCode: UInt16, pressed: Bool, wasPressed: Bool) {
        if pressed && !wasPressed { keySim.pressKey(keyCode) }
        else if !pressed && wasPressed { keySim.releaseKey(keyCode) }
    }

    // MARK: - Delta accumulator

    nonisolated private func accumulateDelta(_ dx: Int, _ dy: Int) {
        accumulatorLock.lock()
        _accumulatedDX += dx
        _accumulatedDY += dy
        accumulatorLock.unlock()
    }

    nonisolated private func consumeAccumulatedDelta() -> (dx: Int, dy: Int) {
        accumulatorLock.lock()
        let dx = _accumulatedDX
        let dy = _accumulatedDY
        _accumulatedDX = 0
        _accumulatedDY = 0
        accumulatorLock.unlock()
        return (dx, dy)
    }
}

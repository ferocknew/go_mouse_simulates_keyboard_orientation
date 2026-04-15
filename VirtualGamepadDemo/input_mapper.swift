//
//  input_mapper.swift
//  VirtualGamepadDemo
//

import Foundation
import CoreGraphics

nonisolated final class InputMapper: @unchecked Sendable {
    var sensitivity: Float = 1.0
    var acceleration: Float = 1.5
    var decayRate: Float = 0.85
    var triggerDecayRate: Float = 0.80

    private var stickX: Float = 0.0
    private var stickY: Float = 0.0
    private var leftTrigger: Float = 0.0
    private var rightTrigger: Float = 0.0
    private var buttonStates: UInt16 = 0

    private let baseMultiplier: Float = 3000.0
    private let deadZone: Float = 1500.0
    private let maxValue: Float = 32767.0

    func processMouseDelta(_ dx: Int, _ dy: Int) {
        let mappedX = mapDeltaToAxis(Float(dx))
        let mappedY = mapDeltaToAxis(Float(dy))

        stickX = stickX * 0.5 + mappedX * 0.5
        stickY = stickY * 0.5 + mappedY * 0.5
    }

    func processScroll(_ delta: Int) {
        let magnitude: Float = 32767.0
        if delta > 0 {
            rightTrigger = magnitude
        } else if delta < 0 {
            leftTrigger = magnitude
        }
    }

    func setButton(_ index: Int, pressed: Bool) {
        guard index >= 0 && index < 16 else { return }
        let bit: UInt16 = UInt16(1 << index)
        if pressed {
            buttonStates |= bit
        } else {
            buttonStates &= ~bit
        }
    }

    func decayTick() {
        // Decay sticks toward center
        stickX *= decayRate
        stickY *= decayRate
        if abs(stickX) < deadZone { stickX = 0 }
        if abs(stickY) < deadZone { stickY = 0 }

        // Decay triggers
        leftTrigger *= triggerDecayRate
        rightTrigger *= triggerDecayRate
        if leftTrigger < 1000 { leftTrigger = 0 }
        if rightTrigger < 1000 { rightTrigger = 0 }
    }

    func currentReport() -> GamepadReport {
        var report = GamepadReport()
        report.buttons = buttonStates
        report.leftStickX = clampToAxis(stickX)
        report.leftStickY = clampToAxis(-stickY)  // Invert Y for game convention
        report.rightStickX = 0
        report.rightStickY = 0
        report.leftTrigger = Int16(min(max(leftTrigger, 0), maxValue))
        report.rightTrigger = Int16(min(max(rightTrigger, 0), maxValue))
        return report
    }

    func reset() {
        stickX = 0
        stickY = 0
        leftTrigger = 0
        rightTrigger = 0
        buttonStates = 0
    }

    private func mapDeltaToAxis(_ delta: Float) -> Float {
        let scaled = delta * baseMultiplier * sensitivity / 20.0

        let accelerated: Float
        if abs(scaled) > 1.0 {
            accelerated = copysignf(powf(abs(scaled), acceleration), scaled)
        } else {
            accelerated = scaled
        }

        return max(-maxValue, min(maxValue, accelerated))
    }

    private func clampToAxis(_ value: Float) -> Int16 {
        let clamped = max(-maxValue, min(maxValue, value))
        return Int16(clamped)
    }
}

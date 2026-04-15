//
//  key_simulator.swift
//  VirtualGamepadDemo
//

import Foundation
import CoreGraphics
import ApplicationServices

nonisolated final class KeySimulator: @unchecked Sendable {
    // keycodes
    static let keyCodeW: UInt16 = 13     // W
    static let keyCodeA: UInt16 = 0      // A
    static let keyCodeS: UInt16 = 1      // S
    static let keyCodeD: UInt16 = 2      // D
    static let keyCodeUp: UInt16 = 126   // Arrow Up
    static let keyCodeDown: UInt16 = 125 // Arrow Down
    static let keyCodeLeft: UInt16 = 123 // Arrow Left
    static let keyCodeRight: UInt16 = 124 // Arrow Right

    // Button keys (configurable)
    var buttonAKeyCode: UInt16 = 38       // J = A button (left click)
    var buttonBKeyCode: UInt16 = 40       // K = B button (right click)
    var buttonCKeyCode: UInt16 = 32       // U = C button (middle click)
    var buttonDKeyCode: UInt16 = 34       // I = D button (button 4)

    private var pressedKeys: Set<UInt16> = []

    func pressKey(_ keyCode: UInt16) {
        guard !pressedKeys.contains(keyCode) else { return }
        pressedKeys.insert(keyCode)
        postKeyEvent(keyCode: keyCode, keyDown: true)
    }

    func releaseKey(_ keyCode: UInt16) {
        guard pressedKeys.contains(keyCode) else { return }
        pressedKeys.remove(keyCode)
        postKeyEvent(keyCode: keyCode, keyDown: false)
    }

    func releaseAll() {
        for keyCode in pressedKeys {
            postKeyEvent(keyCode: keyCode, keyDown: false)
        }
        pressedKeys.removeAll()
    }

    func isPressed(_ keyCode: UInt16) -> Bool {
        return pressedKeys.contains(keyCode)
    }

    private func postKeyEvent(keyCode: UInt16, keyDown: Bool) {
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        )
        event?.post(tap: .cghidEventTap)
    }
}

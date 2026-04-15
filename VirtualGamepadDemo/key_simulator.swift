//
//  key_simulator.swift
//  VirtualGamepadDemo
//

import Foundation
import CoreGraphics
import ApplicationServices

nonisolated final class KeySimulator: @unchecked Sendable {
    // 方向键 keyCode
    static let keyCodeUp: UInt16 = 126
    static let keyCodeDown: UInt16 = 125
    static let keyCodeLeft: UInt16 = 123
    static let keyCodeRight: UInt16 = 124

    private var pressedKeys: Set<UInt16> = []

    // 按键名称 → keyCode 映射表（排除 Ctrl 和 Esc）
    static let keyMap: [(name: String, keyCode: UInt16)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5), ("Z", 6), ("X", 7),
        ("C", 8), ("V", 9), ("B", 11), ("Q", 12), ("W", 13), ("E", 14), ("R", 15),
        ("Y", 16), ("T", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22),
        ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29),
        ("]", 30), ("O", 31), ("U", 32), ("[", 33), ("I", 34), ("P", 35),
        ("Return", 36), ("L", 37), ("J", 38), ("'", 40), ("K", 40),
        (";", 41), ("\\", 42), (",", 43), ("/", 44), ("N", 45), ("M", 46),
        ("Tab", 48), ("Space", 49), ("`", 50),
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96),
        ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109),
        ("F11", 103), ("F12", 111),
        ("Delete", 51), ("Home", 115), ("End", 119),
        ("PageUp", 116), ("PageDown", 121),
    ]

    static func keyCode(for name: String) -> UInt16? {
        // 不允许 Ctrl 和 Esc
        if name == "Ctrl" || name == "Esc" { return nil }
        return keyMap.first(where: { $0.name == name })?.keyCode
    }

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

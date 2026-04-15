//
//  keyboard_monitor.swift
//  VirtualGamepadDemo
//

import Foundation
import AppKit

nonisolated final class KeyboardMonitor: @unchecked Sendable {
    var onToggleHotkey: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        // Global monitor for when app is not focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor for when app has focus
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let isCtrl = event.modifierFlags.contains(.control)
        let isEsc = event.keyCode == 53  // Escape key

        if isCtrl && isEsc {
            onToggleHotkey?()
        }
    }

    deinit {
        stop()
    }
}

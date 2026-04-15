//
//  VirtualGamepadDemoApp.swift
//  VirtualGamepadDemo
//

import SwiftUI

@main
struct VirtualGamepadDemoApp: App {
    @State private var controller = GamepadController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

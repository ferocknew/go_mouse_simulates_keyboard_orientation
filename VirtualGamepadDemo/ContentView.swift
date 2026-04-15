//
//  ContentView.swift
//  VirtualGamepadDemo
//

import SwiftUI

struct ContentView: View {
    @Environment(GamepadController.self) private var controller

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Virtual Gamepad")
                    .font(.title2.bold())
                Spacer()
                Circle()
                    .fill(controller.isCaptured ? .green : .gray)
                    .frame(width: 12, height: 12)
            }

            // Status
            Text(controller.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            // Joystick visual
            VStack(spacing: 8) {
                Text("摇杆 (鼠标移动)")
                    .font(.caption.bold())
                joystickView
            }

            Divider()

            // Buttons
            VStack(spacing: 8) {
                Text("按钮")
                    .font(.caption.bold())
                HStack(spacing: 16) {
                    gamepadButton(label: "A", subtitle: "左键→\(controller.buttonAKeyName)", pressed: controller.buttonA)
                    gamepadButton(label: "B", subtitle: "右键→\(controller.buttonBKeyName)", pressed: controller.buttonB)
                    gamepadButton(label: "C", subtitle: "中键→\(controller.buttonCKeyName)", pressed: controller.buttonC)
                    gamepadButton(label: "D", subtitle: "侧键→\(controller.buttonDKeyName)", pressed: controller.buttonD)
                }
            }

            Divider()

            // System buttons
            HStack(spacing: 24) {
                sysButton(label: "Select", key: controller.selectKeyName)
                sysButton(label: "Start", key: controller.startKeyName)
            }

            Divider()

            // Sensitivity
            SensitivitySlider(controller: controller)

            Divider()

            // Capture button
            Button {
                controller.toggleCapture()
            } label: {
                Label(
                    controller.isCaptured ? "释放鼠标" : "捕获鼠标",
                    systemImage: controller.isCaptured ? "lock.open" : "lock"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isCaptured ? .red : .accentColor)
            .disabled(!controller.accessibilityGranted)

            Text("Ctrl + Esc 释放鼠标")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            controller.setup()
        }
    }

    // MARK: - Joystick

    private var joystickView: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 120, height: 120)

            // Direction indicators
            directionArrow("↑", active: controller.isUp, offset: -40)
            directionArrow("↓", active: controller.isDown, offset: 40)
            directionArrow("←", active: controller.isLeft, offsetX: -40)
            directionArrow("→", active: controller.isRight, offsetX: 40)

            // Center dot
            Circle()
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: 16, height: 16)
        }
        .frame(width: 120, height: 120)
    }

    private func directionArrow(_ symbol: String, active: Bool, offset: CGFloat = 0, offsetX: CGFloat = 0) -> some View {
        Text(symbol)
            .font(.title3)
            .foregroundStyle(active ? Color.accentColor : Color.gray.opacity(0.4))
            .offset(x: offsetX, y: offset)
    }

    // MARK: - Button

    private func gamepadButton(label: String, subtitle: String, pressed: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(pressed ? Color.accentColor : Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(label)
                    .font(.title3.bold())
                    .foregroundStyle(pressed ? .white : .secondary)
            }
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func sysButton(label: String, key: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 60, height: 28)
                .overlay {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            Text("→ \(key)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

struct SensitivitySlider: View {
    @Bindable var controller: GamepadController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("灵敏度")
                .font(.caption.bold())
            HStack {
                Slider(value: $controller.sensitivity, in: 1.0...10.0, step: 0.5)
                Text(String(format: "%.1f", controller.sensitivity))
                    .font(.caption.monospaced())
                    .frame(width: 36)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(GamepadController())
}

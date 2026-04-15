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

            // Joystick visual (8 directions)
            VStack(spacing: 8) {
                Text("摇杆 (鼠标移动)")
                    .font(.caption.bold())
                joystickView
            }

            Divider()

            // 2 buttons with key selector
            VStack(spacing: 12) {
                Text("按钮")
                    .font(.caption.bold())
                HStack(spacing: 24) {
                    buttonConfig(
                        label: "A",
                        subtitle: "左键",
                        keyName: $controller.buttonAKeyName,
                        pressed: controller.buttonA
                    )
                    buttonConfig(
                        label: "B",
                        subtitle: "右键",
                        keyName: $controller.buttonBKeyName,
                        pressed: controller.buttonB
                    )
                }
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

    // MARK: - Joystick (8 directions)

    private var joystickView: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 140, height: 140)

            // 8 directions
            directionArrow("↑", active: controller.isUp, offsetY: -45)
            directionArrow("↓", active: controller.isDown, offsetY: 45)
            directionArrow("←", active: controller.isLeft, offsetX: -45)
            directionArrow("→", active: controller.isRight, offsetX: 45)
            // Diagonals
            directionArrow("↖", active: controller.isUp && controller.isLeft, offsetX: -35, offsetY: -35)
            directionArrow("↗", active: controller.isUp && controller.isRight, offsetX: 35, offsetY: -35)
            directionArrow("↙", active: controller.isDown && controller.isLeft, offsetX: -35, offsetY: 35)
            directionArrow("↘", active: controller.isDown && controller.isRight, offsetX: 35, offsetY: 35)

            Circle()
                .fill(Color.accentColor.opacity(0.8))
                .frame(width: 16, height: 16)
        }
        .frame(width: 140, height: 140)
    }

    private func directionArrow(_ symbol: String, active: Bool, offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> some View {
        Text(symbol)
            .font(.title3)
            .foregroundStyle(active ? Color.accentColor : Color.gray.opacity(0.3))
            .offset(x: offsetX, y: offsetY)
    }

    // MARK: - Button config with picker

    private func buttonConfig(label: String, subtitle: String, keyName: Binding<String>, pressed: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(pressed ? Color.accentColor : Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
                Text(label)
                    .font(.title3.bold())
                    .foregroundStyle(pressed ? .white : .secondary)
            }
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Picker("按键", selection: keyName) {
                ForEach(GamepadController.availableKeys, id: \.self) { key in
                    Text(key).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 100)
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

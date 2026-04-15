//
//  ContentView.swift
//  VirtualGamepadDemo
//

import SwiftUI

struct ContentView: View {
    @Environment(GamepadController.self) private var controller

    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection

            Divider()

            // Status indicators
            statusSection

            Divider()

            // Toggle button
            toggleSection

            Divider()

            // Axis visualization
            axesSection

            Divider()

            // Trigger visualization
            triggersSection

            Divider()

            // Button states
            buttonsSection

            Divider()

            // Sensitivity control
            sensitivitySection
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            controller.setup()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "gamecontroller.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Virtual Gamepad")
                .font(.title2.bold())
            Spacer()
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow(
                icon: controller.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: controller.accessibilityGranted ? .green : .red,
                label: "辅助功能权限",
                value: controller.accessibilityGranted ? "已授权" : "未授权"
            )
            statusRow(
                icon: controller.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: controller.isConnected ? .green : .red,
                label: "虚拟设备",
                value: controller.isConnected ? "已连接" : "未连接"
            )
            statusRow(
                icon: controller.isActive ? "circle.fill" : "circle",
                color: controller.isActive ? .orange : .gray,
                label: "拦截状态",
                value: controller.isActive ? "拦截中" : "已暂停"
            )
        }
    }

    private func statusRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    // MARK: - Toggle

    private var toggleSection: some View {
        VStack(spacing: 8) {
            Button {
                controller.toggleInterception()
            } label: {
                Text(controller.isActive ? "停止拦截" : "开始拦截")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isActive ? .red : .accentColor)
            .disabled(!controller.accessibilityGranted || !controller.isConnected)

            Text("快捷键: Ctrl + Esc")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Axes

    private var axesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("左摇杆")
                .font(.caption.bold())
            axisBar(label: "X", value: controller.lastReport.leftStickX, max: 32767)
            axisBar(label: "Y", value: controller.lastReport.leftStickY, max: 32767)
        }
    }

    private func axisBar(label: String, value: Int16, max: Int16) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.monospaced())
                .frame(width: 16, alignment: .leading)
            GeometryReader { geo in
                let normalized = CGFloat(value) / CGFloat(max)
                let barWidth = geo.size.width
                let center = barWidth / 2

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.6))
                        .frame(width: abs(normalized) * center)
                        .offset(x: normalized >= 0 ? center : center - abs(normalized) * center)
                    Rectangle()
                        .fill(Color.secondary)
                        .frame(width: 1)
                        .offset(x: center)
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text("\(value)")
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Triggers

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("扳机")
                .font(.caption.bold())
            triggerBar(label: "L", value: controller.lastReport.leftTrigger)
            triggerBar(label: "R", value: controller.lastReport.rightTrigger)
        }
    }

    private func triggerBar(label: String, value: Int16) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.monospaced())
                .frame(width: 16, alignment: .leading)
            ProgressView(value: Float(value), total: 32767.0)
                .progressViewStyle(.linear)
            Text("\(value)")
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("按钮")
                .font(.caption.bold())
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    let isPressed = (controller.lastReport.buttons >> i) & 1 == 1
                    Circle()
                        .fill(isPressed ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Text("\(i + 1)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(isPressed ? .white : .secondary)
                        }
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    let label = buttonLabel(i)
                    Text(label)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                }
            }
        }
    }

    private func buttonLabel(_ index: Int) -> String {
        switch index {
        case 0: return "LMB"
        case 1: return "RMB"
        case 2: return "MMB"
        default: return ""
        }
    }

    // MARK: - Sensitivity

    private var sensitivitySection: some View {
        SensitivitySlider(controller: controller)
    }
}

struct SensitivitySlider: View {
    @Bindable var controller: GamepadController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("灵敏度")
                .font(.caption.bold())
            HStack {
                Slider(value: $controller.sensitivity, in: 0.1...5.0, step: 0.1)
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

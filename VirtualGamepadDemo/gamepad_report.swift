//
//  gamepad_report.swift
//  VirtualGamepadDemo
//

import Foundation

nonisolated struct GamepadReport {
    var buttons: UInt16 = 0
    var hatSwitch: UInt8 = 0x08  // 0-7 directions, 8 = neutral
    var leftStickX: Int16 = 0    // -32768..32767, center = 0
    var leftStickY: Int16 = 0
    var rightStickX: Int16 = 0
    var rightStickY: Int16 = 0
    var leftTrigger: Int16 = 0   // 0 = released, 32767 = full
    var rightTrigger: Int16 = 0

    static var zero: GamepadReport {
        GamepadReport()
    }

    mutating func setButton(_ index: Int, pressed: Bool) {
        guard index >= 0 && index < 16 else { return }
        let bit: UInt16 = UInt16(1 << index)
        if pressed {
            buttons |= bit
        } else {
            buttons &= ~bit
        }
    }

    func toBytes() -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 15)

        // Bytes 0-1: Buttons (little-endian)
        report[0] = UInt8(buttons & 0xFF)
        report[1] = UInt8((buttons >> 8) & 0xFF)

        // Byte 2: Hat switch (low nibble) + padding (high nibble)
        report[2] = hatSwitch & 0x0F

        // Bytes 3-14: Axes (little-endian Int16)
        writeInt16(&report, offset: 3, value: leftStickX)
        writeInt16(&report, offset: 5, value: leftStickY)
        writeInt16(&report, offset: 7, value: rightStickX)
        writeInt16(&report, offset: 9, value: rightStickY)
        writeInt16(&report, offset: 11, value: leftTrigger)
        writeInt16(&report, offset: 13, value: rightTrigger)

        return report
    }

    private func writeInt16(_ buffer: inout [UInt8], offset: Int, value: Int16) {
        let u16 = UInt16(bitPattern: value)
        buffer[offset] = UInt8(u16 & 0xFF)
        buffer[offset + 1] = UInt8((u16 >> 8) & 0xFF)
    }
}

// MARK: - HID Report Descriptor

nonisolated enum GamepadHID {
    static let reportDescriptor: [UInt8] = [
        0x05, 0x01,        // Usage Page (Generic Desktop Ctrls)
        0x09, 0x05,        // Usage (Game Pad)
        0xA1, 0x01,        // Collection (Application)

        // 16 Buttons (2 bytes)
        0x05, 0x09,        //   Usage Page (Button)
        0x19, 0x01,        //   Usage Minimum (Button 1)
        0x29, 0x10,        //   Usage Maximum (Button 16)
        0x15, 0x00,        //   Logical Minimum (0)
        0x25, 0x01,        //   Logical Maximum (1)
        0x75, 0x01,        //   Report Size (1)
        0x95, 0x10,        //   Report Count (16)
        0x81, 0x02,        //   Input (Data,Var,Abs)

        // Hat Switch (D-pad, 4 bits)
        0x05, 0x01,        //   Usage Page (Generic Desktop Ctrls)
        0x09, 0x39,        //   Usage (Hat Switch)
        0x15, 0x00,        //   Logical Minimum (0)
        0x25, 0x07,        //   Logical Maximum (7)
        0x35, 0x00,        //   Physical Minimum (0)
        0x46, 0x3B, 0x01,  //   Physical Maximum (315)
        0x65, 0x14,        //   Unit (Degrees)
        0x75, 0x04,        //   Report Size (4)
        0x95, 0x01,        //   Report Count (1)
        0x81, 0x42,        //   Input (Data,Var,Abs,Null State)

        // Padding (4 bits)
        0x75, 0x04,        //   Report Size (4)
        0x95, 0x01,        //   Report Count (1)
        0x81, 0x01,        //   Input (Const,Array,Abs)

        // 6 Axes: LX, LY, RX, RY, LTrigger, RTrigger (16-bit each)
        0x05, 0x01,        //   Usage Page (Generic Desktop Ctrls)
        0x09, 0x30,        //   Usage (X)
        0x09, 0x31,        //   Usage (Y)
        0x09, 0x32,        //   Usage (Z)
        0x09, 0x35,        //   Usage (Rz)
        0x09, 0x33,        //   Usage (Rx)
        0x09, 0x34,        //   Usage (Ry)
        0x16, 0x00, 0x80,  //   Logical Minimum (-32768)
        0x26, 0xFF, 0x7F,  //   Logical Maximum (32767)
        0x75, 0x10,        //   Report Size (16)
        0x95, 0x06,        //   Report Count (6)
        0x81, 0x02,        //   Input (Data,Var,Abs)

        0xC0               // End Collection
    ]
}

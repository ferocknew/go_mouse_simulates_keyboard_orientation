//
//  virtual_hid_device.swift
//  VirtualGamepadDemo
//

import Foundation
import IOKit

nonisolated final class VirtualHIDDevice: @unchecked Sendable {
    private var userDevice: IOHIDUserDevice?
    private let queue = DispatchQueue(label: "com.virtualgamepad.hid")

    var isConnected: Bool {
        return userDevice != nil
    }

    func create() -> Bool {
        let descriptorData = Data(GamepadHID.reportDescriptor)

        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: descriptorData,
            kIOHIDVendorIDKey as String: 0x045E,
            kIOHIDProductIDKey as String: 0x028E,
            kIOHIDProductKey as String: "Virtual Gamepad",
            kIOHIDTransportKey as String: "Virtual",
            kIOHIDVersionNumberKey as String: 0x0100,
            kIOHIDCountryCodeKey as String: 0,
            kIOHIDPrimaryUsagePageKey as String: 0x01,
            kIOHIDPrimaryUsageKey as String: 0x05,
        ]

        guard let cfProperties = properties as CFDictionary? else {
            print("Failed to create CFDictionary for HID device properties")
            return false
        }

        let device = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            cfProperties,
            0  // options
        )
        guard let device = device else {
            print("Failed to create IOHIDUserDevice")
            return false
        }

        userDevice = device

        IOHIDUserDeviceSetDispatchQueue(device, queue)
        IOHIDUserDeviceActivate(device)

        print("Virtual HID gamepad device created successfully")
        return true
    }

    func sendReport(_ report: GamepadReport) {
        guard let device = userDevice else { return }

        let bytes = report.toBytes()
        let timestamp = mach_absolute_time()
        let result: IOReturn = bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return kIOReturnError }
            return IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                timestamp,
                baseAddress,
                CFIndex(bytes.count)
            )
        }

        if result != kIOReturnSuccess {
            print("Failed to send HID report: \(result)")
        }
    }

    func close() {
        guard let device = userDevice else { return }
        IOHIDUserDeviceCancel(device)
        userDevice = nil
        print("Virtual HID device closed")
    }

    deinit {
        close()
    }
}

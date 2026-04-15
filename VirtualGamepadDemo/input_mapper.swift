//
//  input_mapper.swift
//  VirtualGamepadDemo
//

import Foundation

/// 鼠标移动 → 方向键状态（D-pad + X摇杆同时模拟）
nonisolated final class DirectionState: @unchecked Sendable {
    var threshold: Float = 3.0
    var releaseThreshold: Float = 1.0

    private var accumX: Float = 0
    private var accumY: Float = 0
    private let decayRate: Float = 0.88

    var isUp: Bool = false
    var isDown: Bool = false
    var isLeft: Bool = false
    var isRight: Bool = false

    func addDelta(_ dx: Int, _ dy: Int) {
        accumX += Float(dx)
        accumY += Float(dy)
        update()
    }

    func decay() {
        accumX *= decayRate
        accumY *= decayRate
        if abs(accumX) < releaseThreshold { accumX = 0 }
        if abs(accumY) < releaseThreshold { accumY = 0 }
        update()
    }

    func reset() {
        accumX = 0
        accumY = 0
        isUp = false
        isDown = false
        isLeft = false
        isRight = false
    }

    private func update() {
        isUp = accumY < -threshold
        isDown = accumY > threshold
        isLeft = accumX < -threshold
        isRight = accumX > threshold
    }
}

//
//  MotionManager.swift
//

import Foundation
import SwiftUI

#if os(iOS)
import CoreMotion

struct MotionData {
    var gravity: SIMD3<Float>
    var userAcceleration: SIMD3<Float>
    var roll: Float
    var pitch: Float
}

final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    
    // Shake detection
    private var previousAcceleration: SIMD3<Float> = .zero
    private var shakeDetectionThreshold: Float = 2.5
    private var lastShakeTime: TimeInterval = 0
    private let shakeCooldown: TimeInterval = 0.2
    
    func startUpdates(handler: @escaping (MotionData) -> Void, 
                     shakeHandler: @escaping (Float) -> Void) {
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            
            let gravity = SIMD3<Float>(
                Float(data.gravity.x),
                Float(data.gravity.y),
                Float(data.gravity.z)
            )
            
            let userAccel = SIMD3<Float>(
                Float(data.userAcceleration.x),
                Float(data.userAcceleration.y),
                Float(data.userAcceleration.z)
            )
            
            let motionData = MotionData(
                gravity: gravity,
                userAcceleration: userAccel,
                roll: Float(data.attitude.roll),
                pitch: Float(data.attitude.pitch)
            )
            
            // Detect shake from high user acceleration
            let accelMagnitude = length(userAccel)
            let jerk = length(userAccel - self.previousAcceleration)
            self.previousAcceleration = userAccel
            
            let currentTime = CACurrentMediaTime()
            if (accelMagnitude > self.shakeDetectionThreshold || jerk > self.shakeDetectionThreshold * 1.5) &&
               (currentTime - self.lastShakeTime) > self.shakeCooldown {
                self.lastShakeTime = currentTime
                DispatchQueue.main.async {
                    shakeHandler(accelMagnitude)
                }
            }
            
            DispatchQueue.main.async {
                handler(motionData)
            }
        }
    }

    func stopUpdates() {
        motion.stopDeviceMotionUpdates()
    }
}
#else
struct MotionData {
    var gravity: SIMD3<Float> = .zero
    var userAcceleration: SIMD3<Float> = .zero
    var roll: Float = 0
    var pitch: Float = 0
}

final class MotionManager: ObservableObject {
    func startUpdates(handler: @escaping (MotionData) -> Void,
                     shakeHandler: @escaping (Float) -> Void) { }
    func stopUpdates() { }
}
#endif

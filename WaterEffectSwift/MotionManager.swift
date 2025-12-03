//
//  MotionManager.swift
//

import Foundation
import SwiftUI

#if os(iOS)
import CoreMotion

final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    func startUpdates(handler: @escaping (CGFloat, CGFloat) -> Void) {
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: queue) { data, _ in
            guard let attitude = data?.attitude else { return }
            DispatchQueue.main.async {
                handler(CGFloat(attitude.roll), CGFloat(attitude.pitch))
            }
        }
    }

    func stopUpdates() {
        motion.stopDeviceMotionUpdates()
    }
}
#else
final class MotionManager: ObservableObject {
    func startUpdates(handler: @escaping (CGFloat, CGFloat) -> Void) { }
    func stopUpdates() { }
}
#endif

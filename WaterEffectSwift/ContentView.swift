// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @StateObject private var rippleEngine = RippleEngine()

    var body: some View {
#if os(iOS)
        GeometryReader { geo in
            MetalRippleView(rippleEngine: rippleEngine)
                .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                rippleEngine.addTouch(at: value.location, in: geo.size)
                            })
                .onAppear {
                    motionManager.startUpdates { x, y in
                        rippleEngine.applyTilt(dx: x, dy: y)
                    }
                }
                .onDisappear {
                    motionManager.stopUpdates()
                }
                .ignoresSafeArea()
        }
#else
        Text("Water effect is only supported on iOS.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }
}

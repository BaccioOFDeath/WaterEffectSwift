// MetalRippleView.swift
import SwiftUI
import MetalKit

struct MetalRippleView: UIViewRepresentable {
    @ObservedObject var rippleEngine: RippleEngine

    func makeCoordinator() -> Coordinator {
        Coordinator(rippleEngine: rippleEngine)
    }

    func makeUIView(context: Context) -> MTKView {
        let device = RippleRenderer.shared.device
        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.delegate = context.coordinator
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // No-op; the MTKView will continuously render via the coordinator
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let rippleEngine: RippleEngine
        weak var view: MTKView?

        init(rippleEngine: RippleEngine) {
            self.rippleEngine = rippleEngine
            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            self.view = view
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable else { return }
            let sz = CGSize(width: view.drawableSize.width, height: view.drawableSize.height)
            rippleEngine.renderDrawable(to: drawable, withSize: sz)
        }
    }
}

// RippleEngine.swift
import MetalKit
import SwiftUI

final class RippleEngine: ObservableObject {
    private var pendingTouches: [(x: Int, y: Int, value: Float)] = []
    private let lock = NSLock()

    func addTouch(at p: CGPoint, in vs: CGSize) {
        // Guard against invalid view size
        guard vs.width > 0, vs.height > 0 else { return }
        // Convert to texture space (0 .. width-1, 0 .. height-1) using renderer texture size
        let t = RippleRenderer.shared.textures[RippleRenderer.shared.src]
        let rawX = Int((p.x / vs.width) * CGFloat(t.width))
        let rawY = Int((1 - p.y / vs.height) * CGFloat(t.height))
        // Clamp coordinates to valid texture range
        let x = max(0, min(rawX, t.width - 1))
        let y = max(0, min(rawY, t.height - 1))
        lock.lock(); defer { lock.unlock() }
        pendingTouches.append((x: x, y: y, value: 1.0))
    }

    func applyTilt(dx: CGFloat, dy: CGFloat) {
        // Optional: use motion to bias ripple simulation (not implemented yet)
    }

    func renderDrawable(to dr: CAMetalDrawable, withSize vs: CGSize) {
        guard let cb = RippleRenderer.shared.commandQueue.makeCommandBuffer() else { return }

        // Flush pending touches onto the source texture on the CPU side in a thread-safe way
        lock.lock()
        let touches = pendingTouches
        pendingTouches.removeAll()
        lock.unlock()

        if !touches.isEmpty {
            // Write impulses into the current source texture before compute pass.
            // We write small float values for each touched texel using replaceRegion on the CPU thread.
            let tex = RippleRenderer.shared.textures[RippleRenderer.shared.src]
            let width = tex.width
            let height = tex.height
            for t in touches {
                // Ensure each touch lies within the texture bounds (defensive)
                guard t.x >= 0, t.y >= 0, t.x < width, t.y < height else { continue }
                var v = t.value
                let region = MTLRegionMake2D(t.x, t.y, 1, 1)
                tex.replace(region: region, mipmapLevel: 0, withBytes: &v, bytesPerRow: MemoryLayout<Float>.stride)
            }
        }

        RippleRenderer.shared.encodeRipples(into: cb)
        let rp = RippleRenderer.shared.makeRenderPass(for: dr.texture)
        guard let re = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        RippleRenderer.shared.encodeRenderPass(re, size: vs)
        re.endEncoding()
        cb.present(dr)
        cb.commit()
    }
}

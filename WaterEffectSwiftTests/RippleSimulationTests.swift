import XCTest
@testable import WaterEffectSwift

final class RippleSimulationTests: XCTestCase {
    // Helper to zero both simulation textures
    private func zeroTextures(_ renderer: RippleRenderer) {
        let w = renderer.textures[0].width
        let h = renderer.textures[0].height
        let count = w * h
        let byteCount = count * MemoryLayout<Float>.stride
        var zeros = [Float](repeating: 0, count: count)
        for tex in renderer.textures {
            let region = MTLRegionMake2D(0, 0, w, h)
            tex.replace(region: region, mipmapLevel: 0, withBytes: &zeros, bytesPerRow: w * MemoryLayout<Float>.stride)
        }
    }

    func testSingleImpulseProducesNeighborValues() {
        let renderer = RippleRenderer.shared
        // Ensure textures exists
        XCTAssertEqual(renderer.textures.count, 3)
        let tex = renderer.textures[renderer.src]
        let w = tex.width
        let h = tex.height
        XCTAssertGreaterThan(w, 0)
        XCTAssertGreaterThan(h, 0)

        zeroTextures(renderer)

        let cx = w / 2
        let cy = h / 2

        // Write an impulse at the center
        var v: Float = 1.0
        tex.replace(region: MTLRegionMake2D(cx, cy, 1, 1), mipmapLevel: 0, withBytes: &v, bytesPerRow: MemoryLayout<Float>.stride)

        // Run several compute steps to allow propagation in the scheme
        for _ in 0..<4 {
            guard let cb = renderer.commandQueue.makeCommandBuffer() else { XCTFail("cmdBuf"); return }
            renderer.encodeRipples(into: cb)
            cb.commit()
            cb.waitUntilCompleted()
        }

        // Read the entire texture and check that some cells are non-zero and finite
        let outTex = renderer.textures[renderer.src]
        let count = w * h
        var buffer = [Float](repeating: 0, count: count)
        outTex.getBytes(&buffer, bytesPerRow: w * MemoryLayout<Float>.stride, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        var nonzero = 0
        for val in buffer {
            if !val.isFinite { XCTFail("Non-finite value found") }
            if abs(val) > 1e-6 { nonzero += 1 }
        }

        XCTAssertGreaterThan(nonzero, 0, "There should be at least one non-zero texel after propagation")
    }

    func testDampingReducesAmplitudeOverMultipleSteps() {
        let renderer = RippleRenderer.shared
        let tex = renderer.textures[renderer.src]
        let w = tex.width
        let h = tex.height

        zeroTextures(renderer)

        let cx = w / 2
        let cy = h / 2

        var v: Float = 1.0
        tex.replace(region: MTLRegionMake2D(cx, cy, 1, 1), mipmapLevel: 0, withBytes: &v, bytesPerRow: MemoryLayout<Float>.stride)

        func step() -> Float {
            guard let cb = renderer.commandQueue.makeCommandBuffer() else { fatalError("command buffer") }
            renderer.encodeRipples(into: cb)
            cb.commit()
            cb.waitUntilCompleted()
            var out: Float = 0
            renderer.textures[renderer.src].getBytes(&out, bytesPerRow: MemoryLayout<Float>.stride, from: MTLRegionMake2D(cx, cy, 1, 1), mipmapLevel: 0)
            return out
        }

        let first = step()
        // Run several more steps
        var last = first
        for _ in 0..<10 {
            last = step()
        }

        XCTAssertTrue(first.isFinite && last.isFinite)
        // The absolute amplitude after many steps should be less than or equal to the first step magnitude (damping)
        XCTAssertLessThanOrEqual(abs(last), abs(first), "Amplitude should not grow over time")
    }

    func testNoNaNInTextureAfterCompute() {
        let renderer = RippleRenderer.shared
        let tex = renderer.textures[renderer.src]
        let w = tex.width
        let h = tex.height

        zeroTextures(renderer)

        // Place several impulses around center
        let cx = w / 2
        let cy = h / 2
        var v1: Float = 1.0
        var v2: Float = 0.5
        tex.replace(region: MTLRegionMake2D(cx, cy, 1, 1), mipmapLevel: 0, withBytes: &v1, bytesPerRow: MemoryLayout<Float>.stride)
        tex.replace(region: MTLRegionMake2D(cx+1, cy, 1, 1), mipmapLevel: 0, withBytes: &v2, bytesPerRow: MemoryLayout<Float>.stride)

        guard let cb = renderer.commandQueue.makeCommandBuffer() else {
            XCTFail("Failed to create command buffer")
            return
        }
        renderer.encodeRipples(into: cb)
        cb.commit()
        cb.waitUntilCompleted()

        let outTex = renderer.textures[renderer.src]

        // Read entire texture and verify finiteness
        let count = w * h
        var buffer = [Float](repeating: 0, count: count)
        outTex.getBytes(&buffer, bytesPerRow: w * MemoryLayout<Float>.stride, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        for (i, val) in buffer.enumerated() {
            XCTAssertTrue(val.isFinite, "Found non-finite value at index \(i): \(val)")
        }
    }
}

// RippleEngine.swift
import MetalKit
import SwiftUI

/// Touch event with temporal and spatial information for coalescing
struct TouchEvent {
    let position: CGPoint
    let timestamp: TimeInterval
    let force: CGFloat // Normalized 0-1
}

/// Splash particle for visual effects
struct SplashParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var lifetime: Float // 0-1, 1=just spawned, 0=dead
    var size: Float
}

/// Configuration parameters for the water simulation
struct WaterSimConfig {
    var damping: Float = 0.995        // Energy loss per step
    var viscosity: Float = 0.005      // Velocity diffusion
    var waveSpeed: Float = 1.0        // Wave propagation speed
    var normalStrength: Float = 8.0   // Normal map intensity
    var impulseStrength: Float = 0.5  // Touch impulse magnitude
    var impulseRadius: Float = 15.0   // Touch impulse radius in texels
    var velocityScale: Float = 0.01   // Velocity contribution to impulse
    var splashThreshold: Float = 0.3  // Minimum impulse for splash
    var maxParticles: Int = 200       // Maximum splash particles
}

final class RippleEngine: ObservableObject {
    // Touch coalescing and debouncing
    private var pendingTouches: [TouchEvent] = []
    private var lastProcessedPosition: CGPoint?
    private var lastProcessedTime: TimeInterval = 0
    private let touchCoalescingWindow: TimeInterval = 0.016 // ~1 frame at 60fps
    private let spatialDebounceRadius: CGFloat = 5.0 // pixels
    private let lock = NSLock()
    
    // Simulation configuration
    @Published var config = WaterSimConfig()
    
    // Splash particle system
    private var particles: [SplashParticle] = []
    private var particleBuffer: MTLBuffer?
    
    // Motion bias for global tilt
    private var tiltBias: SIMD2<Float> = .zero
    
    // Frame timing for stable integration
    private var lastUpdateTime: TimeInterval = CACurrentMediaTime()
    
    /// Add a touch event with temporal information for coalescing
    func addTouch(at position: CGPoint, in viewSize: CGSize, force: CGFloat = 1.0) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        
        let timestamp = CACurrentMediaTime()
        let event = TouchEvent(position: position, timestamp: timestamp, force: force)
        
        lock.lock()
        defer { lock.unlock() }
        
        pendingTouches.append(event)
    }
    
    /// Process coalesced touches and apply a single smooth impulse
    private func processCoalescedTouches(viewSize: CGSize, commandBuffer: MTLCommandBuffer) {
        lock.lock()
        let touches = pendingTouches
        pendingTouches.removeAll()
        lock.unlock()
        
        guard !touches.isEmpty else { return }
        
        let currentTime = CACurrentMediaTime()
        
        // Filter touches within the coalescing window
        let recentTouches = touches.filter { currentTime - $0.timestamp < touchCoalescingWindow }
        guard !recentTouches.isEmpty else { return }
        
        // Calculate average position and velocity
        var avgPosition = CGPoint.zero
        var avgForce: CGFloat = 0
        
        for touch in recentTouches {
            avgPosition.x += touch.position.x
            avgPosition.y += touch.position.y
            avgForce += touch.force
        }
        
        avgPosition.x /= CGFloat(recentTouches.count)
        avgPosition.y /= CGFloat(recentTouches.count)
        avgForce /= CGFloat(recentTouches.count)
        
        // Calculate velocity from position delta
        var velocity: CGFloat = 0
        if let lastPos = lastProcessedPosition {
            let dx = avgPosition.x - lastPos.x
            let dy = avgPosition.y - lastPos.y
            velocity = sqrt(dx * dx + dy * dy) / CGFloat(currentTime - lastProcessedTime + 0.0001)
        }
        
        // Spatial debouncing: skip if too close to last touch and low velocity
        if let lastPos = lastProcessedPosition {
            let dx = avgPosition.x - lastPos.x
            let dy = avgPosition.y - lastPos.y
            let distance = sqrt(dx * dx + dy * dy)
            
            if distance < spatialDebounceRadius && velocity < 100 {
                return // Too close, treat as same touch
            }
        }
        
        lastProcessedPosition = avgPosition
        lastProcessedTime = currentTime
        
        // Convert to texture space
        let texWidth = RippleRenderer.shared.heightTextures[0].width
        let texHeight = RippleRenderer.shared.heightTextures[0].height
        
        let texX = Float((avgPosition.x / viewSize.width) * CGFloat(texWidth))
        let texY = Float((avgPosition.y / viewSize.height) * CGFloat(texHeight))
        
        // Calculate impulse strength based on force and velocity
        let velocityContribution = min(Float(velocity) * config.velocityScale, 1.0)
        let impulseStrength = config.impulseStrength * Float(avgForce) * (1.0 + velocityContribution)
        
        // Apply impulse via compute shader
        applyImpulse(
            at: SIMD2<Float>(texX, texY),
            strength: impulseStrength,
            radius: config.impulseRadius,
            commandBuffer: commandBuffer
        )
        
        // Spawn splash particles if impulse is strong enough
        if impulseStrength > config.splashThreshold {
            spawnSplashParticles(
                at: avgPosition,
                viewSize: viewSize,
                intensity: impulseStrength
            )
        }
    }
    
    /// Apply a Gaussian impulse to the height field
    private func applyImpulse(at position: SIMD2<Float>, strength: Float, radius: Float, commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = RippleRenderer.shared.impulsePipeline else { return }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(RippleRenderer.shared.heightTextures[0], index: 0)
        
        var pos = position
        var str = strength
        var rad = radius
        
        encoder.setBytes(&pos, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.setBytes(&str, length: MemoryLayout<Float>.stride, index: 1)
        encoder.setBytes(&rad, length: MemoryLayout<Float>.stride, index: 2)
        
        let texWidth = RippleRenderer.shared.heightTextures[0].width
        let texHeight = RippleRenderer.shared.heightTextures[0].height
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let numGroups = MTLSize(
            width: (texWidth + 7) / 8,
            height: (texHeight + 7) / 8,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    /// Spawn splash particles at the touch location
    private func spawnSplashParticles(at position: CGPoint, viewSize: CGSize, intensity: Float) {
        let count = min(Int(intensity * 20), 30) // More particles for stronger touches
        
        for _ in 0..<count {
            // Random angle and speed
            let angle = Float.random(in: 0..<Float.pi * 2)
            let speed = Float.random(in: 50...200) * intensity
            
            let velocity = SIMD2<Float>(
                cos(angle) * speed,
                sin(angle) * speed
            )
            
            let particle = SplashParticle(
                position: SIMD2<Float>(Float(position.x), Float(position.y)),
                velocity: velocity,
                lifetime: 1.0,
                size: Float.random(in: 2...6)
            )
            
            particles.append(particle)
        }
        
        // Limit total particles
        if particles.count > config.maxParticles {
            particles.removeFirst(particles.count - config.maxParticles)
        }
    }
    
    /// Update particle physics
    private func updateParticles(deltaTime: Float) {
        let gravity = SIMD2<Float>(0, 500) // Downward gravity
        let drag: Float = 0.95 // Air resistance
        
        particles = particles.compactMap { particle in
            var p = particle
            
            // Physics update
            p.velocity += gravity * deltaTime
            p.velocity *= drag
            p.position += p.velocity * deltaTime
            
            // Lifetime decay
            p.lifetime -= deltaTime * 2.0 // Particles last ~0.5 seconds
            
            // Remove dead particles
            return p.lifetime > 0 ? p : nil
        }
    }
    
    /// Apply global tilt bias from device motion
    func applyTilt(dx: CGFloat, dy: CGFloat) {
        // Convert tilt to a subtle bias force
        tiltBias = SIMD2<Float>(Float(dx) * 0.01, Float(dy) * 0.01)
    }
    
    /// Main render loop: update simulation and render to drawable
    func renderDrawable(to drawable: CAMetalDrawable, withSize viewSize: CGSize) {
        guard let commandBuffer = RippleRenderer.shared.commandQueue.makeCommandBuffer() else { return }
        
        // Calculate delta time
        let currentTime = CACurrentMediaTime()
        let deltaTime = Float(currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        
        // Calculate stable timestep (CFL condition)
        let dt = min(deltaTime, 0.016) // Cap at 60fps worth of time
        
        // Process coalesced touches
        processCoalescedTouches(viewSize: viewSize, commandBuffer: commandBuffer)
        
        // Update simulation
        RippleRenderer.shared.updateSimulation(
            commandBuffer: commandBuffer,
            config: config,
            dt: dt,
            tiltBias: tiltBias
        )
        
        // Update particles
        updateParticles(deltaTime: dt)
        
        // Render
        let renderPass = RippleRenderer.shared.makeRenderPass(for: drawable.texture)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        
        RippleRenderer.shared.encodeRenderPass(encoder, size: viewSize)
        
        // Render particles
        if !particles.isEmpty {
            RippleRenderer.shared.renderParticles(encoder, particles: particles, viewSize: viewSize)
        }
        
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

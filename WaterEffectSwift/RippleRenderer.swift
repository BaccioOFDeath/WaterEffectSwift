// RippleRenderer.swift
import Metal
import MetalKit

/// SimParams structure matching Metal shader
struct SimParams {
    var damping: Float
    var viscosity: Float
    var waveSpeed: Float
    var dt: Float
    var tiltBias: SIMD2<Float>
    var boundaryDamping: Float
}

/// Visual rendering parameters
struct RenderParams {
    var refractionScale: Float
    var specularStrength: Float
    var fresnelStrength: Float
    var rimLightIntensity: Float
    var foamIntensity: Float
}

final class RippleRenderer {
    static let shared = RippleRenderer()
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Compute pipelines
    private var heightUpdatePipeline: MTLComputePipelineState!
    private var velocityUpdatePipeline: MTLComputePipelineState!
    private var normalsPipeline: MTLComputePipelineState!
    private var foamPipeline: MTLComputePipelineState!
    var impulsePipeline: MTLComputePipelineState!
    var anisotropicImpulsePipeline: MTLComputePipelineState!
    
    // Render pipelines
    private var renderPipeline: MTLRenderPipelineState!
    private var particlePipeline: MTLRenderPipelineState!
    
    // Simulation textures (ping-pong buffers)
    var heightTextures: [MTLTexture] = [] // Two textures for ping-pong
    var velocityTextures: [MTLTexture] = [] // Two textures for ping-pong (now RG format for 2D velocity)
    var normalTexture: MTLTexture!
    var foamTexture: MTLTexture!
    var backgroundTexture: MTLTexture!
    
    private var currentHeightIndex = 0
    private var currentVelocityIndex = 0
    
    // Rendering resources
    private var quadBuffer: MTLBuffer!
    private var sampler: MTLSamplerState!
    
    // Simulation resolution (configurable)
    let simWidth = 512
    let simHeight = 512
    
    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        device = dev
        
        guard let cq = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        commandQueue = cq
        
        buildPipelines()
        buildResources()
    }
    
    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default library")
        }
        
        // Compute pipelines
        heightUpdatePipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "height_update")!
        )
        
        velocityUpdatePipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "velocity_update")!
        )
        
        normalsPipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "normals_from_height")!
        )
        
        impulsePipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "apply_impulse")!
        )
        
        anisotropicImpulsePipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "apply_impulse_anisotropic")!
        )
        
        foamPipeline = try! device.makeComputePipelineState(
            function: library.makeFunction(name: "compute_foam")!
        )
        
        // Render pipeline for water surface
        let renderDesc = MTLRenderPipelineDescriptor()
        renderDesc.vertexFunction = library.makeFunction(name: "quad_vert")
        renderDesc.fragmentFunction = library.makeFunction(name: "quad_frag")
        renderDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        let vertexDesc = MTLVertexDescriptor()
        vertexDesc.attributes[0].format = .float2
        vertexDesc.attributes[0].offset = 0
        vertexDesc.attributes[0].bufferIndex = 0
        vertexDesc.attributes[1].format = .float2
        vertexDesc.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDesc.attributes[1].bufferIndex = 0
        vertexDesc.layouts[0].stride = MemoryLayout<Float>.stride * 4
        vertexDesc.layouts[0].stepFunction = .perVertex
        
        renderDesc.vertexDescriptor = vertexDesc
        renderPipeline = try! device.makeRenderPipelineState(descriptor: renderDesc)
        
        // Particle pipeline
        let particleDesc = MTLRenderPipelineDescriptor()
        particleDesc.vertexFunction = library.makeFunction(name: "particle_vert")
        particleDesc.fragmentFunction = library.makeFunction(name: "particle_frag")
        particleDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        // Enable blending for particles
        particleDesc.colorAttachments[0].isBlendingEnabled = true
        particleDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDesc.colorAttachments[0].destinationRGBBlendFactor = .one
        particleDesc.colorAttachments[0].rgbBlendOperation = .add
        particleDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleDesc.colorAttachments[0].destinationAlphaBlendFactor = .zero
        particleDesc.colorAttachments[0].alphaBlendOperation = .add
        
        let particleVertexDesc = MTLVertexDescriptor()
        particleVertexDesc.attributes[0].format = .float2 // position
        particleVertexDesc.attributes[0].offset = 0
        particleVertexDesc.attributes[0].bufferIndex = 0
        particleVertexDesc.attributes[1].format = .float2 // velocity
        particleVertexDesc.attributes[1].offset = MemoryLayout<Float>.stride * 2
        particleVertexDesc.attributes[1].bufferIndex = 0
        particleVertexDesc.attributes[2].format = .float // lifetime
        particleVertexDesc.attributes[2].offset = MemoryLayout<Float>.stride * 4
        particleVertexDesc.attributes[2].bufferIndex = 0
        particleVertexDesc.attributes[3].format = .float // size
        particleVertexDesc.attributes[3].offset = MemoryLayout<Float>.stride * 5
        particleVertexDesc.attributes[3].bufferIndex = 0
        particleVertexDesc.layouts[0].stride = MemoryLayout<Float>.stride * 6
        particleVertexDesc.layouts[0].stepFunction = .perVertex
        
        particleDesc.vertexDescriptor = particleVertexDesc
        particlePipeline = try! device.makeRenderPipelineState(descriptor: particleDesc)
    }
    
    private func buildResources() {
        // Create height textures (ping-pong)
        let heightDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: simWidth,
            height: simHeight,
            mipmapped: false
        )
        heightDesc.usage = [.shaderRead, .shaderWrite]
        heightDesc.storageMode = .shared
        
        heightTextures = [
            device.makeTexture(descriptor: heightDesc)!,
            device.makeTexture(descriptor: heightDesc)!
        ]
        
        // Create velocity textures (ping-pong) - now RG format for 2D velocity
        let velocityDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg32Float,
            width: simWidth,
            height: simHeight,
            mipmapped: false
        )
        velocityDesc.usage = [.shaderRead, .shaderWrite]
        velocityDesc.storageMode = .shared
        
        velocityTextures = [
            device.makeTexture(descriptor: velocityDesc)!,
            device.makeTexture(descriptor: velocityDesc)!
        ]
        
        // Create normal map texture
        let normalDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: simWidth,
            height: simHeight,
            mipmapped: false
        )
        normalDesc.usage = [.shaderRead, .shaderWrite]
        normalDesc.storageMode = .shared
        
        normalTexture = device.makeTexture(descriptor: normalDesc)!
        
        // Create foam texture
        let foamDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: simWidth,
            height: simHeight,
            mipmapped: false
        )
        foamDesc.usage = [.shaderRead, .shaderWrite]
        foamDesc.storageMode = .shared
        
        foamTexture = device.makeTexture(descriptor: foamDesc)!
        
        // Create background texture with a procedural pattern
        backgroundTexture = createBackgroundTexture()
        
        // Initialize textures to zero
        initializeTextures()
        
        // Create fullscreen quad
        let quad: [Float] = [
            -1, -1, 0, 1,  // bottom-left
             1, -1, 1, 1,  // bottom-right
            -1,  1, 0, 0,  // top-left
             1,  1, 1, 0   // top-right
        ]
        quadBuffer = device.makeBuffer(
            bytes: quad,
            length: quad.count * MemoryLayout<Float>.stride,
            options: []
        )
        
        // Create sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDesc)!
    }
    
    private func initializeTextures() {
        // Initialize height textures
        let count = simWidth * simHeight
        let zeros = [Float](repeating: 0, count: count)
        let region = MTLRegionMake2D(0, 0, simWidth, simHeight)
        let bytesPerRowSingle = simWidth * MemoryLayout<Float>.stride
        
        for tex in heightTextures {
            tex.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: zeros,
                bytesPerRow: bytesPerRowSingle
            )
        }
        
        // Initialize velocity textures (RG format, so 2 floats per pixel)
        let velocityZeros = [Float](repeating: 0, count: count * 2)
        let bytesPerRowDouble = simWidth * MemoryLayout<Float>.stride * 2
        
        for tex in velocityTextures {
            tex.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: velocityZeros,
                bytesPerRow: bytesPerRowDouble
            )
        }
    }
    
    private func createBackgroundTexture() -> MTLTexture {
        let width = 512
        let height = 512
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        
        guard let texture = device.makeTexture(descriptor: desc) else {
            fatalError("Failed to create background texture")
        }
        
        // Create a procedural pattern (sand/pebble texture)
        // Pre-allocate pixel buffer
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        
        // Use simple deterministic hash instead of Random for performance
        func hash2D(_ x: Int, _ y: Int) -> Float {
            let h = UInt32(x * 73856093) ^ UInt32(y * 19349663)
            return Float(h % 10000) / 10000.0
        }
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                
                // Create a subtle sand/pebble pattern with deterministic hash
                let noise = hash2D(x, y)
                let baseColor: Float = 0.6 + noise * 0.2
                
                // Add some variation with simple trig pattern
                let patternX = Float(x) / 30.0
                let patternY = Float(y) / 30.0
                let pattern = sin(patternX) * cos(patternY) * 0.1 + 0.9
                
                let finalColor = baseColor * pattern
                
                // Warm sand color (beige/tan)
                pixels[idx + 0] = UInt8(finalColor * 0.95 * 255) // R
                pixels[idx + 1] = UInt8(finalColor * 0.85 * 255) // G
                pixels[idx + 2] = UInt8(finalColor * 0.6 * 255)  // B
                pixels[idx + 3] = 255 // A
            }
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * 4
        )
        
        return texture
    }
    
    /// Update the simulation: height and velocity integration, normal generation, foam
    func updateSimulation(commandBuffer: MTLCommandBuffer, config: WaterSimConfig, dt: Float, tiltBias: SIMD2<Float>) {
        // Prepare simulation parameters
        var params = SimParams(
            damping: config.damping,
            viscosity: config.viscosity,
            waveSpeed: config.waveSpeed,
            dt: dt,
            tiltBias: tiltBias,
            boundaryDamping: config.boundaryDamping
        )
        
        // 1. Update velocity from height gradients
        guard let velocityEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        velocityEncoder.setComputePipelineState(velocityUpdatePipeline)
        
        let heightIn = heightTextures[currentHeightIndex]
        let velocityIn = velocityTextures[currentVelocityIndex]
        let velocityOut = velocityTextures[1 - currentVelocityIndex]
        
        velocityEncoder.setTexture(heightIn, index: 0)
        velocityEncoder.setTexture(velocityIn, index: 1)
        velocityEncoder.setTexture(velocityOut, index: 2)
        velocityEncoder.setBytes(&params, length: MemoryLayout<SimParams>.stride, index: 0)
        
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        let numGroups = MTLSize(
            width: (simWidth + 7) / 8,
            height: (simHeight + 7) / 8,
            depth: 1
        )
        
        velocityEncoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        velocityEncoder.endEncoding()
        
        currentVelocityIndex = 1 - currentVelocityIndex
        
        // 2. Update height from velocity
        guard let heightEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        heightEncoder.setComputePipelineState(heightUpdatePipeline)
        
        let heightOut = heightTextures[1 - currentHeightIndex]
        let velocityCurrent = velocityTextures[currentVelocityIndex]
        
        heightEncoder.setTexture(heightIn, index: 0)
        heightEncoder.setTexture(velocityCurrent, index: 1)
        heightEncoder.setTexture(heightOut, index: 2)
        heightEncoder.setBytes(&params, length: MemoryLayout<SimParams>.stride, index: 0)
        
        heightEncoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        heightEncoder.endEncoding()
        
        currentHeightIndex = 1 - currentHeightIndex
        
        // 3. Generate normals from height field
        guard let normalEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        normalEncoder.setComputePipelineState(normalsPipeline)
        
        normalEncoder.setTexture(heightTextures[currentHeightIndex], index: 0)
        normalEncoder.setTexture(normalTexture, index: 1)
        
        var normalStrength = config.normalStrength
        normalEncoder.setBytes(&normalStrength, length: MemoryLayout<Float>.stride, index: 0)
        
        normalEncoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        normalEncoder.endEncoding()
        
        // 4. Compute foam from curvature and velocity
        guard let foamEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        foamEncoder.setComputePipelineState(foamPipeline)
        
        foamEncoder.setTexture(heightTextures[currentHeightIndex], index: 0)
        foamEncoder.setTexture(velocityTextures[currentVelocityIndex], index: 1)
        foamEncoder.setTexture(foamTexture, index: 2)
        
        var foamThreshold = config.foamThreshold
        foamEncoder.setBytes(&foamThreshold, length: MemoryLayout<Float>.stride, index: 0)
        
        foamEncoder.dispatchThreadgroups(numGroups, threadsPerThreadgroup: threadsPerGroup)
        foamEncoder.endEncoding()
    }
    
    /// Create render pass descriptor
    func makeRenderPass(for texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.1, blue: 0.15, alpha: 1.0)
        return descriptor
    }
    
    /// Encode render pass for water surface
    func encodeRenderPass(_ encoder: MTLRenderCommandEncoder, size: CGSize, config: WaterSimConfig) {
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(heightTextures[currentHeightIndex], index: 0)
        encoder.setFragmentTexture(normalTexture, index: 1)
        encoder.setFragmentTexture(foamTexture, index: 2)
        encoder.setFragmentTexture(backgroundTexture, index: 3)
        encoder.setFragmentSamplerState(sampler, index: 0)
        
        // Set visual parameters
        var refractionScale = config.refractionScale
        var specularStrength = config.specularStrength
        var fresnelStrength = config.fresnelStrength
        var rimLightIntensity = config.rimLightIntensity
        var foamIntensity = config.foamIntensity
        
        encoder.setFragmentBytes(&refractionScale, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentBytes(&specularStrength, length: MemoryLayout<Float>.stride, index: 1)
        encoder.setFragmentBytes(&fresnelStrength, length: MemoryLayout<Float>.stride, index: 2)
        encoder.setFragmentBytes(&rimLightIntensity, length: MemoryLayout<Float>.stride, index: 3)
        encoder.setFragmentBytes(&foamIntensity, length: MemoryLayout<Float>.stride, index: 4)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    /// Render splash particles
    func renderParticles(_ encoder: MTLRenderCommandEncoder, particles: [SplashParticle], viewSize: CGSize) {
        guard !particles.isEmpty else { return }
        
        // Pack particle data into buffer
        var particleData: [Float] = []
        for p in particles {
            particleData.append(p.position.x)
            particleData.append(p.position.y)
            particleData.append(p.velocity.x)
            particleData.append(p.velocity.y)
            particleData.append(p.lifetime)
            particleData.append(p.size)
        }
        
        guard let buffer = device.makeBuffer(
            bytes: particleData,
            length: particleData.count * MemoryLayout<Float>.stride,
            options: []
        ) else { return }
        
        encoder.setRenderPipelineState(particlePipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        
        var viewportSize = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))
        encoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particles.count)
    }
}

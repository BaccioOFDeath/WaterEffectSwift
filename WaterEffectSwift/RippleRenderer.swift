// RippleRenderer.swift
import Metal
import MetalKit

/// SimParams structure matching Metal shader
struct SimParams {
    var damping: Float
    var viscosity: Float
    var waveSpeed: Float
    var dt: Float
}

final class RippleRenderer {
    static let shared = RippleRenderer()
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Compute pipelines
    private var heightUpdatePipeline: MTLComputePipelineState!
    private var velocityUpdatePipeline: MTLComputePipelineState!
    private var normalsPipeline: MTLComputePipelineState!
    var impulsePipeline: MTLComputePipelineState!
    
    // Render pipelines
    private var renderPipeline: MTLRenderPipelineState!
    private var particlePipeline: MTLRenderPipelineState!
    
    // Simulation textures (ping-pong buffers)
    var heightTextures: [MTLTexture] = [] // Two textures for ping-pong
    var velocityTextures: [MTLTexture] = [] // Two textures for ping-pong
    var normalTexture: MTLTexture!
    
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
        
        // Create velocity textures (ping-pong)
        let velocityDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
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
        let count = simWidth * simHeight
        let zeros = [Float](repeating: 0, count: count)
        let region = MTLRegionMake2D(0, 0, simWidth, simHeight)
        let bytesPerRow = simWidth * MemoryLayout<Float>.stride
        
        for tex in heightTextures + velocityTextures {
            tex.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: zeros,
                bytesPerRow: bytesPerRow
            )
        }
    }
    
    /// Update the simulation: height and velocity integration, normal generation
    func updateSimulation(commandBuffer: MTLCommandBuffer, config: WaterSimConfig, dt: Float, tiltBias: SIMD2<Float>) {
        // Prepare simulation parameters
        var params = SimParams(
            damping: config.damping,
            viscosity: config.viscosity,
            waveSpeed: config.waveSpeed,
            dt: dt
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
    func encodeRenderPass(_ encoder: MTLRenderCommandEncoder, size: CGSize) {
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(heightTextures[currentHeightIndex], index: 0)
        encoder.setFragmentTexture(normalTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
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

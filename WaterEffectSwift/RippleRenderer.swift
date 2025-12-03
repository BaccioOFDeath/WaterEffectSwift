// RippleRenderer.swift
import Metal
import MetalKit

final class RippleRenderer {
    static let shared = RippleRenderer()
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var computePipeline: MTLComputePipelineState!
    private var renderPipeline: MTLRenderPipelineState!
    private var damping: Float = 0.99
    var textures: [MTLTexture] = [] // will contain prev, curr, out
    // src will point to the current 'curr' texture index within textures
    var src = 1
    private var quadBuffer: MTLBuffer!

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
        let lib = device.makeDefaultLibrary()!
        let kfn = lib.makeFunction(name: "ripple_update")!
        computePipeline = try! device.makeComputePipelineState(function: kfn)
        let vfn = lib.makeFunction(name: "quad_vert")!, ffn = lib.makeFunction(name: "quad_frag")!
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Provide a vertex descriptor because the vertex function uses input attributes
        let vertexDescriptor = MTLVertexDescriptor()
        // attribute 0 = float2 position (offset 0)
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // attribute 1 = float2 uv (offset 2 * float)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        // layout: stride = 4 floats per vertex
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        desc.vertexDescriptor = vertexDescriptor

        renderPipeline = try! device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildResources() {
        let size = 512
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: size, height: size, mipmapped: false)
        td.usage = [.shaderRead, .shaderWrite]
        td.storageMode = .shared
        // create three textures: prev(0), curr(1), out(2)
        textures = [device.makeTexture(descriptor: td)!, device.makeTexture(descriptor: td)!, device.makeTexture(descriptor: td)!]
        let quad: [Float] = [-1,-1,0,1, 1,-1,1,1, -1,1,0,0, 1,1,1,0]
        quadBuffer = device.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<Float>.stride, options: [])
    }

    func makeRenderPass(for tex: MTLTexture) -> MTLRenderPassDescriptor {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture      = tex
        d.colorAttachments[0].loadAction   = .clear
        d.colorAttachments[0].storeAction  = .store
        d.colorAttachments[0].clearColor   = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
        return d
    }

    func encodeRipples(into cb: MTLCommandBuffer) {
        guard computePipeline != nil else { return }
        let ce = cb.makeComputeCommandEncoder()!
        ce.setComputePipelineState(computePipeline)
        // prev = textures[(src+2)%3], curr = textures[src], out = textures[(src+1)%3]
        let prevIndex = (src + 2) % 3
        let outIndex = (src + 1) % 3
        ce.setTexture(textures[prevIndex], index: 0)
        ce.setTexture(textures[src], index: 1)
        ce.setTexture(textures[outIndex], index: 2)
        var d = damping
        ce.setBytes(&d, length: MemoryLayout<Float>.stride, index: 0)

        let texWidth = textures[0].width
        let texHeight = textures[0].height
        let maxTotal = computePipeline.maxTotalThreadsPerThreadgroup
        let threadExecutionWidth = computePipeline.threadExecutionWidth

        let tgWidth = min(threadExecutionWidth, texWidth)
        let tgHeight = max(1, min(maxTotal / tgWidth, texHeight))

        let threadsPerThreadgroup = MTLSize(width: tgWidth, height: tgHeight, depth: 1)
        let threadgroupsPerGrid = MTLSize(width: (texWidth + tgWidth - 1) / tgWidth,
                                         height: (texHeight + tgHeight - 1) / tgHeight,
                                         depth: 1)

        ce.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        ce.endEncoding()
        // rotate: after compute, out becomes curr, curr becomes prev
        src = outIndex
    }

    func encodeRenderPass(_ re: MTLRenderCommandEncoder, size: CGSize) {
        re.setRenderPipelineState(renderPipeline)
        re.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        re.setFragmentTexture(textures[src], index: 0)
        let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())!
        re.setFragmentSamplerState(sampler, index: 0)
        re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

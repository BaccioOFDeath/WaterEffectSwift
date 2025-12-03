#include <metal_stdlib>
using namespace metal;

kernel void ripple_update(texture2d<float, access::read>  prevTex  [[ texture(0) ]],
                          texture2d<float, access::read>  currTex  [[ texture(1) ]],
                          texture2d<float, access::write> outTex   [[ texture(2) ]],
                          constant float &damping                   [[ buffer(0) ]],
                          uint2 gid                                  [[ thread_position_in_grid ]]) {
    uint2 size = uint2(currTex.get_width(), currTex.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;

    float center = currTex.read(gid).r;
    uint2 leftCoord  = uint2(gid.x == 0 ? 0 : gid.x - 1, gid.y);
    uint2 rightCoord = uint2(gid.x + 1 >= size.x ? size.x - 1 : gid.x + 1, gid.y);
    uint2 upCoord    = uint2(gid.x, gid.y == 0 ? 0 : gid.y - 1);
    uint2 downCoord  = uint2(gid.x, gid.y + 1 >= size.y ? size.y - 1 : gid.y + 1);

    float left   = currTex.read(leftCoord).r;
    float right  = currTex.read(rightCoord).r;
    float up     = currTex.read(upCoord).r;
    float down   = currTex.read(downCoord).r;

    // Use previous frame sample to create stable second-order wave simulation
    float prev = prevTex.read(gid).r;
    float h = (left + right + up + down) * 0.5 - prev;
    outTex.write(float4(h * damping), gid);
}

struct QuadVertex { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; };

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut quad_vert(QuadVertex in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.pos, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 quad_frag(VertexOut in [[stage_in]],
                          texture2d<float, access::sample> hm [[texture(0)]],
                          sampler s [[sampler(0)]]) {
    float2 uv = in.uv;
    float h = hm.sample(s, uv).r;
    float g = clamp(h * 0.5 + 0.5, 0.0, 1.0);
    return float4(g, g, g, 1.0);
}

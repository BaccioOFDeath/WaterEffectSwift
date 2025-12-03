#include <metal_stdlib>
using namespace metal;

// Simulation parameters structure
struct SimParams {
    float damping;        // Energy loss per step (0.98-0.995)
    float viscosity;      // Velocity diffusion (0.0-0.01)
    float waveSpeed;      // Wave propagation speed (0.5-2.0)
    float dt;             // Timestep (auto-calculated for stability)
    float2 tiltBias;      // Global acceleration from device tilt
    float boundaryDamping; // Energy loss at boundaries (0.5-0.95)
};

// Shallow-water heightfield update: computes new height from velocity divergence
kernel void height_update(texture2d<float, access::read>  heightIn  [[texture(0)]],
                          texture2d<float, access::read>  velocityIn [[texture(1)]],
                          texture2d<float, access::write> heightOut  [[texture(2)]],
                          constant SimParams &params                 [[buffer(0)]],
                          uint2 gid                                  [[thread_position_in_grid]]) {
    uint2 size = uint2(heightIn.get_width(), heightIn.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    
    float h = heightIn.read(gid).r;
    
    // Read neighbor velocities for divergence calculation
    uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
    uint2 right = uint2(min(gid.x + 1, size.x - 1), gid.y);
    uint2 up    = uint2(gid.x, max(int(gid.y) - 1, 0));
    uint2 down  = uint2(gid.x, min(gid.y + 1, size.y - 1));
    
    float2 vL = velocityIn.read(left).rg;
    float2 vR = velocityIn.read(right).rg;
    float2 vU = velocityIn.read(up).rg;
    float2 vD = velocityIn.read(down).rg;
    
    // Compute velocity divergence: div(v) = dvx/dx + dvy/dy
    float divergence = (vR.x - vL.x) * 0.5 + (vD.y - vU.y) * 0.5;
    
    // Height change is proportional to negative divergence
    float newH = h - divergence * params.dt;
    
    // Apply damping to height
    newH *= params.damping;
    
    heightOut.write(float4(newH, 0, 0, 0), gid);
}

// Shallow-water velocity update: computes new 2D velocity from height gradients
kernel void velocity_update(texture2d<float, access::read>  heightIn    [[texture(0)]],
                            texture2d<float, access::read>  velocityIn  [[texture(1)]],
                            texture2d<float, access::write> velocityOut [[texture(2)]],
                            constant SimParams &params                  [[buffer(0)]],
                            uint2 gid                                   [[thread_position_in_grid]]) {
    uint2 size = uint2(heightIn.get_width(), heightIn.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    
    // Read neighbors with boundary conditions (clamping)
    uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
    uint2 right = uint2(min(gid.x + 1, size.x - 1), gid.y);
    uint2 up    = uint2(gid.x, max(int(gid.y) - 1, 0));
    uint2 down  = uint2(gid.x, min(gid.y + 1, size.y - 1));
    
    float hC = heightIn.read(gid).r;
    float hL = heightIn.read(left).r;
    float hR = heightIn.read(right).r;
    float hU = heightIn.read(up).r;
    float hD = heightIn.read(down).r;
    
    // Compute pressure gradients (negative of height gradients)
    float2 gradient = float2((hR - hL) * 0.5, (hD - hU) * 0.5);
    
    // Read current 2D velocity (stored in RG channels)
    float2 v = velocityIn.read(gid).rg;
    
    // Acceleration from pressure gradient and tilt bias
    float2 acceleration = -params.waveSpeed * params.waveSpeed * gradient + params.tiltBias;
    
    // Update velocity with acceleration
    float2 newV = v + acceleration * params.dt;
    
    // Apply viscosity (velocity damping)
    newV -= params.viscosity * newV;
    
    // Boundary damping: reduce velocity near edges
    float boundaryDist = min(min(float(gid.x), float(size.x - 1 - gid.x)),
                             min(float(gid.y), float(size.y - 1 - gid.y)));
    float boundaryFactor = smoothstep(0.0, 10.0, boundaryDist);
    float edgeDamping = mix(params.boundaryDamping, 1.0, boundaryFactor);
    
    newV *= edgeDamping;
    
    // Apply global damping
    newV *= params.damping;
    
    velocityOut.write(float4(newV.x, newV.y, 0, 0), gid);
}

// Apply a Gaussian impulse to the height field
kernel void apply_impulse(texture2d<float, access::read_write> heightTex [[texture(0)]],
                          constant float2 &position                       [[buffer(0)]],
                          constant float &strength                        [[buffer(1)]],
                          constant float &radius                          [[buffer(2)]],
                          uint2 gid                                       [[thread_position_in_grid]]) {
    uint2 size = uint2(heightTex.get_width(), heightTex.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    
    float2 pos = float2(gid);
    float2 delta = pos - position;
    float dist = length(delta);
    
    if (dist < radius) {
        // Gaussian falloff: exp(-dist^2 / (2 * sigma^2))
        float sigma = radius / 3.0; // 3-sigma rule
        float gaussian = exp(-dist * dist / (2.0 * sigma * sigma));
        
        float currentH = heightTex.read(gid).r;
        float impulse = strength * gaussian;
        float newH = currentH + impulse;
        
        heightTex.write(float4(newH, 0, 0, 0), gid);
    }
}

// Apply an anisotropic Gaussian impulse to the height field (for directional wakes)
kernel void apply_impulse_anisotropic(texture2d<float, access::read_write> heightTex [[texture(0)]],
                                     texture2d<float, access::read_write> velocityTex [[texture(1)]],
                                     constant float2 &position                         [[buffer(0)]],
                                     constant float2 &direction                        [[buffer(1)]],
                                     constant float &strength                          [[buffer(2)]],
                                     constant float &radius                            [[buffer(3)]],
                                     constant float &anisotropy                        [[buffer(4)]],
                                     uint2 gid                                         [[thread_position_in_grid]]) {
    uint2 size = uint2(heightTex.get_width(), heightTex.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    
    float2 pos = float2(gid);
    float2 delta = pos - position;
    
    // Compute anisotropic distance
    constant float kEpsilon = 0.001; // Small value to avoid division by zero
    float2 dirNorm = normalize(direction + float2(kEpsilon));
    float2 perpDir = float2(-dirNorm.y, dirNorm.x);
    
    float alongDist = dot(delta, dirNorm);
    float perpDist = dot(delta, perpDir);
    
    // Stretch in perpendicular direction (wake is narrow along motion)
    float dist = length(float2(alongDist, perpDist / (1.0 + anisotropy)));
    
    if (dist < radius) {
        // Gaussian falloff with anisotropic shape
        float sigma = radius / 3.0;
        float gaussian = exp(-dist * dist / (2.0 * sigma * sigma));
        
        // Apply impulse to height
        float currentH = heightTex.read(gid).r;
        float impulse = strength * gaussian;
        float newH = currentH + impulse;
        heightTex.write(float4(newH, 0, 0, 0), gid);
        
        // Also impart velocity in direction of motion
        float2 currentV = velocityTex.read(gid).rg;
        float2 velocityImpulse = direction * strength * gaussian * 0.5;
        float2 newV = currentV + velocityImpulse;
        velocityTex.write(float4(newV.x, newV.y, 0, 0), gid);
    }
}

// Compute foam mask from height curvature and velocity magnitude
kernel void compute_foam(texture2d<float, access::read>  heightIn  [[texture(0)]],
                         texture2d<float, access::read>  velocityIn [[texture(1)]],
                         texture2d<float, access::write> foamOut    [[texture(2)]],
                         constant float &foamThreshold              [[buffer(0)]],
                         uint2 gid                                  [[thread_position_in_grid]]) {
    uint2 size = uint2(heightIn.get_width(), heightIn.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    
    // Read neighbors for curvature calculation
    uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
    uint2 right = uint2(min(gid.x + 1, size.x - 1), gid.y);
    uint2 up    = uint2(gid.x, max(int(gid.y) - 1, 0));
    uint2 down  = uint2(gid.x, min(gid.y + 1, size.y - 1));
    
    float hC = heightIn.read(gid).r;
    float hL = heightIn.read(left).r;
    float hR = heightIn.read(right).r;
    float hU = heightIn.read(up).r;
    float hD = heightIn.read(down).r;
    
    // Compute Laplacian (curvature)
    float curvature = abs((hL + hR + hU + hD - 4.0 * hC));
    
    // Get velocity magnitude
    float2 v = velocityIn.read(gid).rg;
    float velocityMag = length(v);
    
    // Foam appears at high curvature or high velocity regions
    float foam = smoothstep(foamThreshold, foamThreshold * 2.0, curvature + velocityMag * 0.1);
    
    // Boundary foam: add foam near edges
    float boundaryDist = min(min(float(gid.x), float(size.x - 1 - gid.x)),
                             min(float(gid.y), float(size.y - 1 - gid.y)));
    float boundaryFoam = smoothstep(5.0, 0.0, boundaryDist) * 0.5;
    
    foam = saturate(foam + boundaryFoam);
    
    foamOut.write(float4(foam, foam, foam, 1.0), gid);
}

// Generate normal map from height field using finite differences
kernel void normals_from_height(texture2d<float, access::read>  heightIn  [[texture(0)]],
                                texture2d<float, access::write> normalOut [[texture(1)]],
                                constant float &normalStrength            [[buffer(0)]],
                                uint2 gid                                 [[thread_position_in_grid]]) {
    uint2 size = uint2(heightIn.get_width(), heightIn.get_height());
    if (gid.x >= size.x || gid.y >= size.y) return;
    
    // Sample neighbors for gradient calculation
    uint2 left  = uint2(max(int(gid.x) - 1, 0), gid.y);
    uint2 right = uint2(min(gid.x + 1, size.x - 1), gid.y);
    uint2 up    = uint2(gid.x, max(int(gid.y) - 1, 0));
    uint2 down  = uint2(gid.x, min(gid.y + 1, size.y - 1));
    
    float hL = heightIn.read(left).r;
    float hR = heightIn.read(right).r;
    float hU = heightIn.read(up).r;
    float hD = heightIn.read(down).r;
    
    // Central differences for gradient
    float dx = (hR - hL) * 0.5;
    float dy = (hD - hU) * 0.5;
    
    // Construct normal (scale gradients by normalStrength)
    float3 normal = normalize(float3(-dx * normalStrength, -dy * normalStrength, 1.0));
    
    // Map [-1,1] to [0,1] for storage
    normal = normal * 0.5 + 0.5;
    
    normalOut.write(float4(normal, 1.0), gid);
}

struct QuadVertex { 
    float2 pos [[attribute(0)]]; 
    float2 uv [[attribute(1)]]; 
};

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

// Enhanced fragment shader with realistic water rendering
fragment float4 quad_frag(VertexOut in [[stage_in]],
                          texture2d<float, access::sample> heightMap [[texture(0)]],
                          texture2d<float, access::sample> normalMap [[texture(1)]],
                          texture2d<float, access::sample> foamMap   [[texture(2)]],
                          texture2d<float, access::sample> backgroundTex [[texture(3)]],
                          sampler s [[sampler(0)]],
                          constant float &refractionScale   [[buffer(0)]],
                          constant float &specularStrength  [[buffer(1)]],
                          constant float &fresnelStrength   [[buffer(2)]],
                          constant float &rimLightIntensity [[buffer(3)]],
                          constant float &foamIntensity     [[buffer(4)]]) {
    float2 uv = in.uv;
    
    // Sample height and normal
    float h = heightMap.sample(s, uv).r;
    float3 normal = normalMap.sample(s, uv).rgb;
    
    // Convert normal from [0,1] to [-1,1]
    normal = normal * 2.0 - 1.0;
    normal = normalize(normal);
    
    // Base water color (deep blue)
    float3 waterColorDeep = float3(0.0, 0.05, 0.15);
    float3 waterColorShallow = float3(0.0, 0.15, 0.3);
    
    // Depth-based color mixing (negative h = deeper)
    float depth = -h;
    float depthFactor = smoothstep(-0.5, 0.5, depth);
    float3 baseColor = mix(waterColorShallow, waterColorDeep, depthFactor);
    
    // Lighting setup
    float3 lightDir = normalize(float3(0.5, -0.7, 0.5)); // Light from upper-right
    float3 viewDir = float3(0.0, 0.0, 1.0); // Orthographic view
    
    // Diffuse lighting
    float diffuse = max(dot(normal, -lightDir), 0.0);
    diffuse = diffuse * 0.3 + 0.7; // Soft diffuse
    
    // Specular highlights (Blinn-Phong with Fresnel)
    float3 halfVec = normalize(-lightDir + viewDir);
    float specular = pow(max(dot(normal, halfVec), 0.0), 32.0);
    
    // Fresnel approximation (Schlick's approximation)
    float fresnel = pow(1.0 - max(dot(normal, viewDir), 0.0), 3.0);
    fresnel = mix(1.0, fresnel, fresnelStrength);
    
    specular *= fresnel * specularStrength;
    
    // Rim lighting on steep slopes
    float rim = 1.0 - abs(normal.z);
    rim = pow(rim, 3.0) * rimLightIntensity;
    
    // Refraction distortion (offset UV by normal)
    float2 refractUV = uv + normal.xy * refractionScale;
    refractUV = clamp(refractUV, 0.0, 1.0);
    
    // Sample background texture with refraction
    float3 background = backgroundTex.sample(s, refractUV).rgb;
    
    // Sample foam
    float foam = foamMap.sample(s, uv).r * foamIntensity;
    
    // Combine: base color with lighting, refraction, specular, and rim
    float3 finalColor = baseColor * diffuse;
    finalColor = mix(finalColor, background, 0.3); // Refraction blend
    finalColor += float3(1.0) * specular;           // Specular highlights
    finalColor += float3(0.3, 0.5, 0.7) * rim;     // Rim light
    
    // Add foam (white caps)
    finalColor = mix(finalColor, float3(1.0, 1.0, 1.0), foam);
    
    // Add height-based brightness for visualization
    float brightness = h * 0.1 + 0.5;
    finalColor *= brightness;
    
    return float4(finalColor, 1.0);
}

// Particle vertex shader (for splash effects)
struct ParticleIn {
    float2 position  [[attribute(0)]];
    float2 velocity  [[attribute(1)]];
    float lifetime   [[attribute(2)]];
    float size       [[attribute(3)]];
};

struct ParticleOut {
    float4 position [[position]];
    float lifetime;
    float size      [[point_size]];
};

vertex ParticleOut particle_vert(ParticleIn in [[stage_in]],
                                 constant float2 &viewportSize [[buffer(0)]]) {
    ParticleOut out;
    
    // Convert particle position to NDC
    float2 ndc = (in.position / viewportSize) * 2.0 - 1.0;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    
    out.lifetime = in.lifetime;
    out.size = in.size;
    
    return out;
}

fragment float4 particle_frag(ParticleOut in [[stage_in]],
                              float2 pointCoord [[point_coord]]) {
    // Circular particle with soft edges
    float2 centered = pointCoord * 2.0 - 1.0;
    float dist = length(centered);
    
    if (dist > 1.0) discard_fragment();
    
    float alpha = (1.0 - dist) * in.lifetime;
    
    // Bright white particle with fade
    float3 color = float3(1.0);
    
    return float4(color, alpha);
}

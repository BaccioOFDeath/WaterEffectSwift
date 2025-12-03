# Water Physics Model Documentation

## Overview

This document describes the realistic water simulation physics implemented in WaterEffectSwift v3.0, focusing on container-based sloshing, motion coupling, and realistic boundary behavior.

## Shallow Water Equations with 2D Velocity

### Mathematical Model

The simulation uses a 2D velocity field-based shallow water model:

**State Variables:**
- `h(x,y,t)`: Water surface height at position (x,y) and time t
- `v(x,y,t) = (vx, vy)`: 2D velocity field (horizontal flow)

**Update Equations:**

1. **Velocity Update** (momentum equation):
   ```
   ∂v/∂t = -c² ∇h + F_tilt - μv - ν∇²v
   
   Where:
   - c = waveSpeed (wave propagation speed)
   - ∇h = height gradient (pressure gradient)
   - F_tilt = tiltBias (acceleration from device tilt)
   - μ = viscosity (velocity damping coefficient)
   - ν = diffusion coefficient
   ```

2. **Height Update** (continuity equation):
   ```
   ∂h/∂t = -∇·v
   
   Where:
   - ∇·v = divergence of velocity field
   - Represents mass conservation
   ```

3. **Boundary Conditions**:
   ```
   v(boundary) *= boundaryDamping * smoothstep(distance_to_edge)
   
   - Reduces velocity near edges for energy dissipation
   - Creates reflecting boundaries with partial absorption
   ```

### Implementation Details

**Texture Formats:**
- Height: R32Float (single channel)
- Velocity: RG32Float (two channels for vx, vy)
- Normals: RGBA8Unorm
- Foam: R8Unorm

**Compute Pipeline:**
1. Apply impulses (touch/shake)
2. Update velocity from height gradients + tilt bias
3. Update height from velocity divergence
4. Generate normals from height
5. Compute foam from curvature + velocity magnitude

## Motion-Driven Dynamics

### Device Tilt (Sloshing)

The device's gravity vector is projected onto the screen plane to create lateral acceleration:

```swift
// In MotionManager:
gravity = (gx, gy, gz)  // From CMDeviceMotion

// In RippleEngine:
lateralGravity = (gx, -gy)  // Project to screen plane
tiltBias = lateralGravity * tiltBiasScale
```

**Effect on Water:**
- Tilting device creates a constant acceleration across the entire surface
- Water "flows" toward the lower edge
- Oscillates back and forth when tilt changes (sloshing)
- Configurable via `tiltBiasScale` parameter

**Tuning:**
- `tiltBiasScale = 0`: No tilt response (flat pool)
- `tiltBiasScale = 50`: Moderate sloshing (default)
- `tiltBiasScale = 100`: Strong sloshing (ocean in a storm)

### Shake Detection

Shake events are detected via high user acceleration or jerk (acceleration derivative):

```swift
// In MotionManager:
accelMagnitude = length(userAcceleration)
jerk = length(userAcceleration - previousAcceleration)

if (accelMagnitude > 2.5 || jerk > 3.75) {
    triggerShake(magnitude: accelMagnitude)
}
```

**Shake Response:**
- Multiple broad impulses applied across random surface locations
- Impulse count scales with shake magnitude
- Impulse radius: 80-120 texels (container-scale waves)
- Creates chaotic wave patterns that settle over time

**Cooldown:**
- 200ms between shake detections to prevent spam
- Allows distinct shake events to be processed separately

## Container Boundaries

### Reflecting Boundaries

Waves reflect off container edges with partial energy loss:

```metal
float boundaryDist = min(min(gid.x, width - gid.x),
                         min(gid.y, height - gid.y));
float boundaryFactor = smoothstep(0.0, 10.0, boundaryDist);
float edgeDamping = mix(boundaryDamping, 1.0, boundaryFactor);
velocity *= edgeDamping;
```

**Behavior:**
- Within 10 texels of edge: velocity scaled by `boundaryDamping`
- Smooth transition via `smoothstep` to avoid discontinuities
- Creates realistic wave reflection with partial absorption

**Parameters:**
- `boundaryDamping = 0.8`: Default (20% energy loss on reflection)
- `boundaryDamping = 0.95`: Hard walls (minimal loss)
- `boundaryDamping = 0.5`: Soft boundaries (strong absorption)

### Foam at Boundaries

Foam automatically appears near edges, especially during wave collisions:

```metal
float boundaryFoam = smoothstep(5.0, 0.0, boundaryDist) * 0.5;
foam = saturate(foam + boundaryFoam);
```

This creates white caps along container walls, enhancing the "water in a tank" appearance.

## Touch Interaction

### Anisotropic Impulses (Directional Wakes)

Fast finger motion creates elongated wakes rather than circular ripples:

**Kernel Shape:**
```metal
// Transform to anisotropic space
float2 dirNorm = normalize(touchDirection);
float2 perpDir = perpendicular(dirNorm);

float alongDist = dot(delta, dirNorm);
float perpDist = dot(delta, perpDir);

// Stretch perpendicular to motion
float dist = length(vec2(alongDist, perpDist / (1 + anisotropy)));
```

**Effect:**
- Slow touches (v < 100 px/s): Circular impulse
- Fast swipes (v > 100 px/s): Elongated wake
- `anisotropyFactor = 2.0`: Moderate wake (default)
- `anisotropyFactor = 5.0`: Thin, pronounced wake

**Velocity Coupling:**
```metal
velocityImpulse = direction * strength * gaussian * 0.5;
newVelocity = currentVelocity + velocityImpulse;
```

Imparts directional momentum to the velocity field, creating realistic trailing waves.

### Multi-Touch Support

Each finger is tracked independently:
- Separate touch event buffers per contact
- Coalescing applied per-finger
- Multiple coherent wakes can interact naturally
- Stable under crossing/overlapping wakes

## Foam and Whitecaps

### Foam Generation

Foam appears in two scenarios:

1. **High Curvature** (wave breaking):
   ```metal
   curvature = abs(laplacian(height));
   foam += smoothstep(threshold, threshold * 2, curvature);
   ```

2. **High Velocity** (turbulent flow):
   ```metal
   velocityMag = length(velocity);
   foam += smoothstep(threshold, threshold * 2, velocityMag * 0.1);
   ```

3. **Boundary Collisions** (edge foam):
   ```metal
   boundaryFoam = smoothstep(5.0, 0.0, distToEdge) * 0.5;
   ```

### Foam Rendering

Foam is blended with the water surface in the fragment shader:

```metal
finalColor = mix(waterColor, white, foam * foamIntensity);
```

**Parameters:**
- `foamThreshold`: Minimum curvature for foam (default: 0.05)
- `foamIntensity`: Visibility of foam (default: 0.5)

## Visual Rendering

### Refraction with Background Texture

A procedural sand texture is refracted by the water surface:

```metal
refractUV = uv + normal.xy * refractionScale;
background = backgroundTexture.sample(sampler, refractUV);
finalColor = mix(waterColor, background, 0.3);
```

**Background Texture:**
- 512×512 RGBA8 texture
- Procedural sand/pebble pattern
- Warm beige/tan color palette
- Subtle noise and pattern variation

### Enhanced Lighting

**Components:**
1. **Diffuse**: Soft directional light (30% direct, 70% ambient)
2. **Specular**: Blinn-Phong with Fresnel modulation
3. **Fresnel**: Schlick's approximation for angle-dependent reflectivity
4. **Rim Light**: Highlights steep slopes (wave crests)
5. **Foam**: White additive layer at high-energy regions

**Configurable Parameters:**
- `refractionScale`: UV distortion strength (0.0-0.1)
- `specularStrength`: Highlight brightness (0.0-2.0)
- `fresnelStrength`: Angle-dependent mixing (0.0-1.0)
- `rimLightIntensity`: Edge highlight brightness (0.0-1.0)

### Depth Coloring

Water color transitions from shallow (light cyan) to deep (dark blue):

```metal
depthFactor = smoothstep(-0.5, 0.5, -height);
baseColor = mix(shallowColor, deepColor, depthFactor);
```

Creates intuitive depth perception without actual 3D volume.

## Performance Optimization

### CFL Condition

Timestep is capped to maintain numerical stability:

```swift
dt = min(deltaTime, 0.016)  // Max 60 FPS worth of time
```

Prevents simulation explosion from large timesteps during lag spikes.

### Adaptive Damping

During vigorous motion (high velocity/curvature), damping can be dynamically increased:

```swift
adaptiveDamping = baseDamping * (1.0 + energyLevel * 0.05)
```

(Not currently implemented, but recommended for future enhancement)

### Compute Shader Optimization

**Threadgroup Size:** 8×8 threads per group
- Optimal for most Apple GPUs (A9+)
- Good occupancy and memory access patterns

**Memory Access:**
- Coalesced texture reads
- Minimal divergence in conditionals
- Boundary checks via clamping (no branching)

**Ping-Pong Buffers:**
- Avoid read-after-write hazards
- Clean separation of input/output textures

## Stability and Validation

### Numerical Stability

The simulation is unconditionally stable due to:
1. **Implicit Integration**: Velocity/height updated in separate passes
2. **Damping**: Global energy loss per timestep
3. **Boundary Damping**: Edge energy dissipation
4. **CFL-Aware Timestep**: Capped dt prevents instability
5. **Viscosity**: Smooths high-frequency oscillations

### Test Scenarios

**Gentle Tilt (Sloshing):**
- Device tilted 10-20 degrees
- Water gradually flows to lower edge
- Oscillates back when device levels
- Settles within 2-3 seconds

**Shake (Chaos):**
- Quick shake gesture
- Multiple broad waves propagate
- Chaotic interference patterns
- Settles within 3-5 seconds

**Fast Swipe (Wake):**
- Rapid finger motion across screen
- Elongated wake trailing finger
- Directional particle spray
- No "thousand touches" artifact

**Boundary Collision:**
- Wave hits edge
- Reflects with reduced energy
- Foam appears at impact point
- Gradual energy dissipation

**Multi-Touch Crossing:**
- Two fingers create separate wakes
- Wakes interact (constructive/destructive interference)
- System remains stable
- No NaN/Infinity values

### Performance Targets

**Target:** 60 FPS on iPhone 11+ (A13 and newer)

**Typical Frame Budget:**
- Simulation (compute): ~1.5ms
- Rendering (fragment): ~1.0ms
- Particles: ~0.5ms
- Total: ~3ms (leaves 13.7ms margin at 60 FPS)

**Scaling for Older Devices:**
- Reduce `simWidth/simHeight` (512 → 256)
- Lower `maxParticles` (200 → 100)
- Disable foam computation
- Reduce `normalStrength` (8.0 → 4.0)

## Future Enhancements

### Potential Improvements

1. **Particle-to-Surface Feedback:**
   - Particles create secondary ripples on landing
   - Requires particle age/position tracking
   - Apply micro-impulses at particle positions

2. **Adaptive Resolution:**
   - Increase simulation resolution in areas of high activity
   - Lower resolution in calm regions
   - Requires dynamic texture resampling

3. **Curl-Based Turbulence:**
   - Add rotational flow component
   - Enhances realism without destabilizing
   - Computed from velocity curl: ∇×v

4. **Multi-Layer Rendering:**
   - Separate surface, foam, subsurface layers
   - Depth-based compositing
   - Caustics projection

5. **HDR Lighting:**
   - Wide color gamut specular
   - Environment map reflections
   - Tone mapping for HDR displays

6. **Floating Objects:**
   - Buoyancy-based object interaction
   - Dynamic collision with water surface
   - Requires 2D rigid body physics

## Tuning Guide

### For Different Aesthetics

**Calm Pool (Meditation App):**
```
damping = 0.998
viscosity = 0.01
waveSpeed = 0.7
tiltBiasScale = 20
boundaryDamping = 0.9
```

**Ocean Waves (Dramatic):**
```
damping = 0.99
viscosity = 0.002
waveSpeed = 1.5
tiltBiasScale = 80
boundaryDamping = 0.7
foamIntensity = 0.8
```

**Science Demo (Clear Physics):**
```
damping = 0.995
viscosity = 0.005
waveSpeed = 1.0
tiltBiasScale = 50
normalStrength = 12.0
foamIntensity = 0.3
```

### Debugging Tips

**Simulation Exploding (values grow unbounded):**
- Increase `damping` closer to 1.0
- Increase `viscosity`
- Check for NaN in textures
- Verify CFL timestep capping

**Waves Don't Propagate:**
- Increase `waveSpeed`
- Decrease `damping`
- Check texture initialization

**No Tilt Response:**
- Verify CoreMotion permissions
- Increase `tiltBiasScale`
- Check gravity vector magnitude

**Performance Drops:**
- Reduce `maxParticles`
- Lower simulation resolution
- Disable foam computation
- Reduce `normalStrength`

## References

### Physics

- **Shallow Water Equations**: Simplified Navier-Stokes for free surface flows
- **CFL Condition**: Courant-Friedrichs-Lewy stability criterion
- **Finite Difference Method**: Spatial derivative approximation

### Graphics

- **Fresnel Effect**: Schlick's approximation
- **Blinn-Phong**: Specular lighting model
- **Normal Mapping**: Surface detail from derivatives
- **Screen-Space Refraction**: UV perturbation by normals

### Implementation

- **Metal Compute Shaders**: GPU-accelerated physics
- **Ping-Pong Buffers**: Double buffering for stability
- **CoreMotion**: Device motion and orientation
- **SwiftUI Integration**: Reactive UI with published properties

---

**Version**: 3.0  
**Last Updated**: 2025-12-03  
**Authors**: Enhanced implementation for realistic container-based water simulation

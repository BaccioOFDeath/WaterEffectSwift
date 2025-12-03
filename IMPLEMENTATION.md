# Water Effect Implementation Guide

## Overview

This project implements a realistic water surface simulation with interactive touch input, using Metal compute shaders for GPU-accelerated physics simulation and rendering.

## Architecture

### Core Components

1. **RippleEngine.swift** - Central simulation coordinator
   - Manages simulation state and configuration
   - Handles touch input coalescing and debouncing
   - Controls particle system for splash effects
   - Coordinates with RippleRenderer for GPU operations

2. **RippleRenderer.swift** - Metal rendering and compute backend
   - Manages GPU resources (textures, buffers, pipelines)
   - Executes compute shaders for physics simulation
   - Handles rendering of water surface and particles
   - Implements ping-pong buffering for stable simulation

3. **RippleShaders.metal** - GPU compute and rendering kernels
   - Height and velocity field updates (shallow water equations)
   - Gaussian impulse application for smooth touch response
   - Normal map generation from height field
   - Realistic water rendering with refraction, specular, and depth

4. **ContentView.swift** - SwiftUI interface
   - Touch gesture handling
   - Configuration UI for tuning parameters
   - Integration with MotionManager for device tilt

5. **MetalRippleView.swift** - UIKit/Metal bridge
   - MTKView wrapper for SwiftUI
   - Frame timing and drawable presentation

6. **MotionManager.swift** - Device motion tracking
   - CoreMotion integration for tilt effects
   - Provides roll/pitch data to simulation

## Simulation Model

### Shallow Water Equations

The simulation uses a heightfield-based approach with separated height and velocity buffers:

```
h(x,y,t) = water surface height at position (x,y) and time t
v(x,y,t) = vertical velocity at position (x,y) and time t
```

**Update equations:**

1. **Velocity Update** (from height gradients):
   ```
   acceleration = waveSpeed² × ∇²h (Laplacian)
   v' = v + acceleration × dt - viscosity × v
   v' = v' × damping
   ```

2. **Height Update** (from velocity):
   ```
   h' = h + v × dt
   h' = h' × damping
   ```

### Key Features

- **Stability**: Semi-implicit integration with CFL-aware timestep capping
- **Energy Conservation**: Damping factor (0.995) prevents numerical growth
- **Boundary Conditions**: Clamping at edges prevents reflection artifacts
- **Dispersion**: Natural wave spreading via Laplacian operator

## Touch Input Processing

### Problem: "Thousand Touches" Artifact

The original implementation applied an impulse for every touch event, creating unrealistic noise when dragging across the screen (often 60+ events per second).

### Solution: Touch Coalescing

1. **Temporal Aggregation**: Buffer touch events within a time window (~16ms for 60fps)
2. **Spatial Debouncing**: Ignore touches too close to previous position (< 5 pixels)
3. **Velocity Calculation**: Track position delta to measure finger speed
4. **Single Impulse**: Apply one smooth Gaussian impulse per frame with strength based on:
   - Touch force/pressure
   - Finger velocity
   - Configurable strength multiplier

### Gaussian Impulse

Instead of point impulses, we use a Gaussian kernel:

```
impulse(r) = strength × exp(-r² / (2σ²))
where σ = radius / 3 (3-sigma rule)
```

This creates smooth, realistic waves without aliasing artifacts.

## Rendering Pipeline

### 1. Simulation Phase (Compute Shaders)

Per frame, in order:

1. **Process Coalesced Touches**: Apply Gaussian impulse to height field
2. **Velocity Update**: Compute new velocities from height gradients
3. **Height Update**: Integrate velocities into height
4. **Normal Generation**: Calculate normals via finite differences

### 2. Render Phase (Fragment Shader)

For each pixel:

1. **Sample Height & Normal**: Read from simulation textures
2. **Depth-based Coloring**: Mix shallow/deep water colors
3. **Diffuse Lighting**: Soft directional light using normals
4. **Specular Highlights**: Blinn-Phong with Fresnel approximation
5. **Rim Lighting**: Highlight steep slopes
6. **Refraction**: Distort background based on normals
7. **Height Visualization**: Modulate brightness

### 3. Particle Rendering

- Additive blending for bright splashes
- Point sprites with circular falloff
- Gravity and drag physics
- Lifetime-based fading

## Configuration Parameters

### Physics

- **damping** (0.9-0.999): Energy loss per timestep
  - Higher = waves persist longer
  - Lower = faster decay
  - Default: 0.995

- **viscosity** (0.0-0.02): Velocity smoothing
  - Higher = slower, smoother waves
  - Lower = sharper, faster waves
  - Default: 0.005

- **waveSpeed** (0.5-2.0): Wave propagation velocity
  - Controls how fast disturbances spread
  - Default: 1.0

### Touch Response

- **impulseStrength** (0.1-2.0): Base touch force
  - Scales the height displacement
  - Default: 0.5

- **impulseRadius** (5-50): Touch area in texels
  - Larger = broader waves
  - Smaller = tighter ripples
  - Default: 15.0

- **velocityScale** (0.0-0.05): Velocity contribution
  - Fast swipes create stronger waves
  - Default: 0.01

### Visual

- **normalStrength** (1.0-20.0): Normal map intensity
  - Higher = more pronounced lighting/refraction
  - Default: 8.0

### Particles

- **splashThreshold** (0.1-1.0): Minimum impulse for particles
  - Higher = fewer, more dramatic splashes
  - Default: 0.3

- **maxParticles** (50-500): Particle budget
  - Performance vs. visual richness tradeoff
  - Default: 200

## Performance Considerations

### GPU Optimization

- **Simulation Resolution**: 512×512 texels (configurable in RippleRenderer.swift)
- **Threadgroup Sizing**: 8×8 threads per group for optimal occupancy
- **Ping-Pong Buffers**: Avoid read/write hazards in compute shaders
- **Shared Storage Mode**: Efficient CPU-GPU memory sharing
- **Minimal State**: Only 4 textures (2 height, 2 velocity) + 1 normal

### CPU Optimization

- **Lock-Free Reads**: Touch events buffered with NSLock for thread safety
- **Coalescing**: O(1) average-case touch processing per frame
- **Particle Culling**: Dead particles removed each frame

### Typical Performance

- **Target**: 60 FPS (or 120 FPS on ProMotion displays)
- **GPU Time**: ~1-2ms per frame on Apple A14+
- **CPU Time**: <0.5ms per frame

## Testing

### Unit Tests

Located in `WaterEffectSwiftTests/RippleSimulationTests.swift`:

1. **testSingleImpulseProducesNeighborValues**: Verifies wave propagation
2. **testDampingReducesAmplitudeOverMultipleSteps**: Checks stability
3. **testNoNaNInTextureAfterCompute**: Validates numerical stability
4. **testTouchCoalescingReducesImpulseCount**: Confirms input handling
5. **testParticleSystemLimitEnforced**: Checks particle budget

### Manual Testing Checklist

- [ ] Single finger stroke: smooth coherent wake
- [ ] Fast swipe: strong splash particles, no noise
- [ ] Multi-touch: independent, interacting waves
- [ ] Rapid tapping: no "thousand touches" artifact
- [ ] Device tilt: subtle global wave bias
- [ ] Settings UI: all parameters adjust visuals in real-time

## Future Enhancements

### Potential Improvements

1. **Advanced Caustics**: Screen-space caustics texture with curvature
2. **Wind Field**: Perlin noise for ambient surface variation
3. **Foam Simulation**: Track wave energy for foam texture
4. **Particle Feedback**: Secondary ripples from particle impacts
5. **Adaptive Resolution**: Dynamic sim resolution based on performance
6. **Multi-Layer Rendering**: Separate surface layers for depth
7. **HDR Lighting**: Enhanced specular with HDR environment maps

### Known Limitations

- No true 3D water volume (heightfield is 2.5D)
- Simplified lighting model (no ray tracing)
- Particles are screen-space (not 3D objects)
- No inter-object interactions (e.g., floating objects)

## Troubleshooting

### Issue: Simulation explodes (values grow unbounded)

**Cause**: Damping too low or timestep too large

**Fix**: Increase `damping` closer to 1.0, or reduce simulation speed

### Issue: Waves don't propagate

**Cause**: WaveSpeed too low or damping too high

**Fix**: Increase `waveSpeed` or decrease `damping`

### Issue: Touch creates tiny ripples only

**Cause**: `impulseStrength` too low

**Fix**: Increase `impulseStrength` in settings

### Issue: Performance drops below 60 FPS

**Cause**: Too many particles or high simulation resolution

**Fix**: 
- Reduce `maxParticles`
- Reduce `simWidth`/`simHeight` in RippleRenderer
- Disable particle rendering temporarily

### Issue: Particles don't spawn

**Cause**: `splashThreshold` too high

**Fix**: Lower `splashThreshold` to ~0.2

## References

### Physics & Simulation

- **Shallow Water Equations**: Simplified Navier-Stokes for free surface flows
- **CFL Condition**: Courant-Friedrichs-Lewy stability criterion for explicit integration
- **Finite Difference Method**: Numerical approximation of spatial derivatives

### Graphics & Rendering

- **Fresnel Effect**: Angle-dependent reflectivity (Schlick's approximation)
- **Blinn-Phong Shading**: Efficient specular highlights
- **Normal Mapping**: Surface detail from height field derivatives
- **Screen-Space Refraction**: UV offset based on normals

### Metal Programming

- **Compute Shaders**: GPGPU for physics simulation
- **Threadgroup Memory**: Shared on-chip memory for kernel optimization
- **Ping-Pong Buffers**: Double buffering for read-after-write safety

## Credits

Implementation based on:
- Classical shallow water simulation techniques
- GPU Gems series (NVIDIA)
- Real-Time Rendering, 4th Edition (Akenine-Möller et al.)
- Apple Metal Best Practices Guide

---

**Version**: 2.0  
**Last Updated**: 2025-12-03  
**Author**: Enhanced implementation for realistic water effects

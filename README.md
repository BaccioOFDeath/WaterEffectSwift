# WaterEffectSwift

A realistic, GPU-accelerated water surface simulation for iOS with interactive touch input, built using Swift and Metal.

## Features

✨ **Realistic Physics**
- 2D velocity field-based shallow water equations
- Container boundaries with reflection and absorption
- Device tilt-driven sloshing (gravity-coupled dynamics)
- Shake detection for dramatic wave impulses
- Stable semi-implicit integration with CFL timestep
- Natural wave propagation and dispersion
- Configurable damping, viscosity, and boundary behavior

🎨 **Beautiful Rendering**
- Dynamic normal mapping for lighting
- Procedural background texture with realistic refraction
- Fresnel-based specular highlights
- Foam/whitecap generation from wave curvature
- Depth-based coloring with rim lighting
- Configurable visual parameters (refraction, specular, fresnel, foam)
- Smooth particle effects for splashes

👆 **Smart Touch Handling**
- Touch event coalescing eliminates "thousand touches" artifact
- Anisotropic impulses create directional wakes for fast swipes
- Velocity-based impulse scaling
- Smooth Gaussian impulse distribution
- Multi-touch support with natural wave interaction
- Directional particle spawning along motion path

⚡ **Performance Optimized**
- GPU compute shaders for physics simulation
- Efficient ping-pong buffering
- 60+ FPS on modern iOS devices
- Configurable quality settings

## Quick Start

1. Open `WaterEffectSwift.xcodeproj` in Xcode
2. Select an iOS device or simulator (Metal required)
3. Build and run (⌘R)
4. Touch and drag to create waves
5. Tap the gear icon to adjust simulation parameters

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Device with Metal support (A9+ chip)

## Configuration

The app includes a comprehensive settings panel to adjust:

- **Physics**: Damping, viscosity, wave speed, boundary damping
- **Motion Response**: Tilt sensitivity, shake intensity
- **Touch Response**: Impulse strength, radius, velocity sensitivity, wake elongation
- **Visual**: Normal strength, refraction, specular, fresnel, rim light, foam intensity/threshold
- **Particles**: Splash threshold, particle count, lifetime, size range

## Implementation Details

See documentation for comprehensive guides:
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Architecture and algorithms
- [PHYSICS_MODEL.md](PHYSICS_MODEL.md) - Complete physics model, motion coupling, tuning guide
- [CHANGES.md](CHANGES.md) - Detailed changelog
- [VISUAL_IMPROVEMENTS.md](VISUAL_IMPROVEMENTS.md) - Visual enhancements

## Project Structure

```
WaterEffectSwift/
├── WaterEffectSwift/
│   ├── WaterEffectSwiftApp.swift    # App entry point
│   ├── ContentView.swift            # UI and settings
│   ├── MetalRippleView.swift        # Metal view wrapper
│   ├── RippleEngine.swift           # Simulation coordinator
│   ├── RippleRenderer.swift         # Metal rendering backend
│   ├── RippleShaders.metal          # GPU compute/render shaders
│   └── MotionManager.swift          # Device motion tracking
├── WaterEffectSwiftTests/
│   └── RippleSimulationTests.swift  # Unit tests
└── IMPLEMENTATION.md                # Detailed documentation
```

## Key Improvements (v3.0)

### Physics Enhancements
- ✅ 2D velocity field for realistic directional flow
- ✅ Container boundaries with reflection and absorption
- ✅ Device tilt-driven sloshing behavior
- ✅ Shake detection for dramatic wave impulses
- ✅ Anisotropic impulses for directional wakes

### Visual Enhancements
- ✅ Procedural background texture with refraction
- ✅ Foam/whitecap generation from wave dynamics
- ✅ Configurable rendering parameters (refraction, specular, fresnel, rim light)
- ✅ Enhanced depth perception and lighting

### Previous Improvements (v2.0)
- ✅ Smooth, coalesced touch response
- ✅ Gaussian impulse distribution
- ✅ Realistic water shading
- ✅ Splash particle effects
- ✅ Extensive configuration options

## Testing

Run unit tests:
```bash
xcodebuild test -scheme WaterEffectSwift -destination 'platform=iOS Simulator,name=iPhone 15'
```

Tests cover:
- Wave propagation and stability
- Touch coalescing
- Particle system limits
- Numerical stability (no NaN/infinity)

## Performance Tips

For best performance:
1. Reduce `maxParticles` if framerate drops
2. Lower `normalStrength` for less intensive lighting
3. Test on device (simulators have limited Metal support)
4. Enable ProMotion on supported devices (120 FPS)

## License

This project is open source. See LICENSE for details.

## Contributing

Contributions welcome! Future enhancement ideas:
- Particle-to-surface feedback (secondary ripples from landing particles)
- Advanced caustics rendering (projected onto background)
- Curl-based micro-turbulence for added realism
- Adaptive resolution scaling based on performance
- Floating object interactions with buoyancy
- Multi-layer rendering (surface, foam, subsurface)

## Credits

Built with:
- Swift & SwiftUI
- Metal & Metal Performance Shaders
- Core Motion

Inspired by:
- GPU Gems water simulation techniques
- Real-time shallow water equations
- Interactive fluid dynamics research
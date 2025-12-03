# WaterEffectSwift

A realistic, GPU-accelerated water surface simulation for iOS with interactive touch input, built using Swift and Metal.

## Features

✨ **Realistic Physics**
- Shallow water equations with separated height/velocity fields
- Stable semi-implicit integration
- Natural wave propagation and dispersion
- Configurable damping and viscosity

🎨 **Beautiful Rendering**
- Dynamic normal mapping for lighting
- Fresnel-based specular highlights
- Screen-space refraction/distortion
- Depth-based coloring with rim lighting
- Smooth particle effects for splashes

👆 **Smart Touch Handling**
- Touch event coalescing eliminates "thousand touches" artifact
- Velocity-based impulse scaling
- Smooth Gaussian impulse distribution
- Multi-touch support with natural wave interaction

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

The app includes a settings panel to adjust:

- **Physics**: Damping, viscosity, wave speed
- **Touch Response**: Impulse strength, radius, velocity sensitivity
- **Visual**: Normal map intensity
- **Particles**: Splash threshold, particle count

## Implementation Details

See [IMPLEMENTATION.md](IMPLEMENTATION.md) for a comprehensive guide covering:
- Simulation architecture
- Shallow water equations
- Touch coalescing algorithm
- Rendering pipeline
- Performance optimization
- Testing and validation

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

## Key Improvements (v2.0)

### Before
- ❌ "Thousand touches" artifact from rapid input
- ❌ Unrealistic point-source impulses
- ❌ Simple grayscale visualization
- ❌ No depth or lighting effects
- ❌ Limited configurability

### After
- ✅ Smooth, coalesced touch response
- ✅ Gaussian impulse distribution
- ✅ Realistic water shading with refraction
- ✅ Splash particle effects
- ✅ Extensive configuration options
- ✅ Device motion integration

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

Contributions welcome! Areas for enhancement:
- Advanced caustics rendering
- Wind/noise fields for ambient variation
- Foam simulation
- Particle-to-surface feedback
- Adaptive resolution scaling

## Credits

Built with:
- Swift & SwiftUI
- Metal & Metal Performance Shaders
- Core Motion

Inspired by:
- GPU Gems water simulation techniques
- Real-time shallow water equations
- Interactive fluid dynamics research
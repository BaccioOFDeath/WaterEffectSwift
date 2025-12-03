# Water Effect v3.0 - Validation and Testing Guide

## Overview

This document provides validation scenarios and expected behaviors for the enhanced water simulation. Use these tests to verify that the implementation meets the realistic water behavior goals.

## Validation Scenarios

### 1. Gentle Tilt (Sloshing Behavior)

**How to Test:**
1. Open the app on a physical iOS device
2. Hold device upright (portrait)
3. Slowly tilt device 10-20 degrees to the right
4. Wait 1-2 seconds
5. Slowly return device to upright position

**Expected Behavior:**
- Water gradually flows toward the lower (right) edge
- Creates a sloped surface that follows the tilt
- When device returns to upright, water sloshes back and forth
- Oscillation dampens over 2-3 seconds
- No sudden jumps or discontinuities

**Tuning Parameters:**
- `tiltBiasScale`: 20-80 (lower = subtle, higher = dramatic)
- `damping`: 0.995-0.998 (higher = longer oscillation)
- `boundaryDamping`: 0.7-0.9 (lower = more reflection)

**Success Criteria:**
✅ Water responds smoothly to tilt  
✅ Sloshing looks natural and settles gradually  
✅ No simulation instability or explosion  
✅ 60 FPS maintained throughout  

---

### 2. Device Shake (Chaotic Waves)

**How to Test:**
1. Hold device firmly
2. Perform quick shake gesture (like shaking a bottle)
3. Observe water behavior
4. Wait for waves to settle

**Expected Behavior:**
- Multiple broad waves appear across the surface
- Waves propagate in different directions
- Creates chaotic interference patterns
- Settles gradually over 3-5 seconds
- Splash particles may appear at boundaries

**Tuning Parameters:**
- `shakeImpulseScale`: 1.0-5.0 (higher = stronger waves)
- `boundaryDamping`: 0.6-0.8 (lower = more boundary splashing)
- `foamIntensity`: 0.5-1.0 (higher = more visible foam during chaos)

**Success Criteria:**
✅ Shake is detected reliably  
✅ Multiple waves created (not just one)  
✅ Waves interact naturally  
✅ System remains stable (no NaN/Infinity)  
✅ Settles to calm surface  

---

### 3. Single Finger Stroke (Coherent Wake)

**How to Test:**
1. Place finger on screen
2. Drag slowly across screen (< 100 px/s)
3. Observe wake pattern

**Expected Behavior:**
- Single smooth wake follows finger path
- Circular ripples emanate from touch point
- No noise or "thousand touches" artifact
- Wake spreads naturally outward
- Gentle splash particles may appear

**Tuning Parameters:**
- `impulseStrength`: 0.3-1.0
- `impulseRadius`: 10-25
- `splashThreshold`: 0.3-0.5

**Success Criteria:**
✅ One coherent wake (not many small ripples)  
✅ Smooth, clean appearance  
✅ No visual noise or artifacts  
✅ Wake looks like finger dragged through water  

---

### 4. Fast Swipe (Anisotropic Wake)

**How to Test:**
1. Place finger on screen
2. Swipe quickly across screen (> 200 px/s)
3. Observe wake shape and particle spray

**Expected Behavior:**
- Elongated wake trailing finger motion
- Wake is narrower perpendicular to motion
- Particles spray in direction of motion
- Stronger waves than slow stroke
- Dramatic splash effect

**Tuning Parameters:**
- `velocityScale`: 0.01-0.03
- `anisotropyFactor`: 2.0-5.0 (higher = thinner wake)
- `maxImpulsePerFrame`: 3.0-8.0

**Success Criteria:**
✅ Wake is visibly elongated (not circular)  
✅ Direction of wake matches swipe direction  
✅ Particles follow motion path  
✅ Stronger visual impact than slow stroke  

---

### 5. Multi-Touch Interaction

**How to Test:**
1. Place two fingers on screen
2. Drag both fingers in different directions
3. Cross paths of both wakes
4. Observe interaction

**Expected Behavior:**
- Two independent wakes
- Wakes interact where they meet
- Constructive interference (peaks add)
- Destructive interference (peaks cancel)
- System remains stable
- No visual glitches

**Success Criteria:**
✅ Both wakes visible and distinct  
✅ Natural wave interference patterns  
✅ No flickering or instability  
✅ Performance remains at 60 FPS  

---

### 6. Boundary Collision

**How to Test:**
1. Create a strong wave near one edge (fast swipe)
2. Let wave travel to boundary
3. Observe reflection behavior
4. Check for foam at boundary

**Expected Behavior:**
- Wave reflects off boundary
- Reflection is visible but weaker than incident wave
- Foam appears at boundary during strong impacts
- Reflected wave travels back across surface
- Energy gradually dissipates

**Tuning Parameters:**
- `boundaryDamping`: 0.6-0.9 (lower = more reflection)
- `foamIntensity`: 0.3-0.8
- `foamThreshold`: 0.03-0.1

**Success Criteria:**
✅ Clear wave reflection visible  
✅ Reflection is weaker (not equal to incident)  
✅ Foam appears at impact point  
✅ No hard discontinuity at boundary  

---

### 7. Particle Feedback (Secondary Ripples)

**How to Test:**
1. Create strong splash (fast swipe near edge)
2. Observe particles as they fall
3. Watch for small ripples when particles land

**Expected Behavior:**
- Particles arc upward, then fall with gravity
- When particles land (near bottom of screen), tiny ripples appear
- Secondary ripples are much smaller than primary waves
- Subtle effect, not overwhelming

**Tuning Parameters:**
- `particleFeedbackStrength`: 0.1-0.5
- `particleLifetime`: 0.3-0.8

**Success Criteria:**
✅ Particles visible and fall naturally  
✅ Small ripples appear when particles land  
✅ Secondary ripples don't overwhelm primary waves  
✅ Effect is subtle but noticeable  

---

### 8. Visual Quality (Rendering)

**How to Test:**
1. Observe water at rest
2. Create gentle waves
3. Look at specular highlights
4. Check refraction of background
5. Observe foam in high-energy areas

**Expected Behavior:**
- Water has blue color (not gray)
- Specular highlights sparkle on wave peaks
- Background texture is visible and refracted
- Foam appears white on steep waves
- Depth shading (shallow = light, deep = dark)
- Rim lighting on wave edges

**Tuning Parameters:**
- `normalStrength`: 4.0-12.0
- `refractionScale`: 0.01-0.05
- `specularStrength`: 0.5-1.5
- `fresnelStrength`: 0.3-0.7
- `rimLightIntensity`: 0.2-0.5
- `foamIntensity`: 0.3-0.8

**Success Criteria:**
✅ Looks like water (not a heightmap)  
✅ Lighting enhances 3D appearance  
✅ Background texture visible through water  
✅ Foam appears in appropriate places  
✅ Visually appealing aesthetic  

---

### 9. Performance (60 FPS Target)

**How to Test:**
1. Enable FPS counter (Xcode debug gauge)
2. Perform various interactions:
   - Rapid multi-touch
   - Shake while touching
   - Maximum particles spawned
3. Monitor frame rate

**Expected Behavior:**
- Maintains 60 FPS on iPhone 11+ (A13 and newer)
- May drop to 40-50 FPS on iPhone 8 (A11)
- No sudden framerate spikes or stuttering
- Consistent frame pacing

**Optimization if Needed:**
- Reduce `maxParticles`: 200 → 100
- Lower simulation resolution: 512 → 256 (requires code change)
- Reduce `normalStrength`: 8.0 → 4.0
- Disable foam: `foamIntensity` = 0

**Success Criteria:**
✅ 60 FPS on modern devices (A13+)  
✅ Acceptable performance on older devices (A11+)  
✅ Smooth, consistent frame pacing  
✅ No perceptible lag during interaction  

---

### 10. Stability (Long-Duration Test)

**How to Test:**
1. Leave app running for 5 minutes
2. Periodically interact with water
3. Perform various gestures (touch, tilt, shake)
4. Monitor for any degradation

**Expected Behavior:**
- No memory leaks
- No gradual performance degradation
- Simulation remains stable
- No accumulation of NaN/Infinity values
- Particles don't accumulate beyond limit

**Success Criteria:**
✅ Memory usage remains constant  
✅ Performance doesn't degrade over time  
✅ No crashes or hangs  
✅ Simulation behaves consistently  

---

## Known Limitations

### What Works Well
- Container-based sloshing from tilt
- Wave reflection at boundaries
- Anisotropic wakes from fast swipes
- Foam generation
- Particle feedback
- Visual realism

### Current Limitations
1. **2.5D Simulation**: Water is a heightfield, can't model overhangs or breaking waves
2. **No Floating Objects**: Would require separate collision system
3. **Screen-Space Particles**: Not true 3D objects, don't occlude properly
4. **Simplified Lighting**: No ray tracing, global illumination, or caustics
5. **Fixed Boundary**: Container shape is always rectangular
6. **No Wind**: Ambient disturbances not implemented (could add via noise field)

### Future Enhancements
- Curl-based turbulence for micro-detail
- Adaptive resolution (high detail where needed)
- Environment map reflections
- Projected caustics
- Obstacle collision (add walls, objects in water)
- Custom container shapes

---

## Troubleshooting

### Issue: Simulation Explodes (Values Grow Unbounded)

**Symptoms:**
- Water surface becomes extremely distorted
- Bright or dark flashing
- Frame rate drops
- May see NaN warnings in console

**Fixes:**
1. Increase `damping` → 0.998
2. Increase `viscosity` → 0.01
3. Reduce `waveSpeed` → 0.8
4. Check `dt` is capped correctly in code
5. Verify texture format matches shader expectations

---

### Issue: No Tilt Response

**Symptoms:**
- Device tilt doesn't affect water
- Water remains flat regardless of orientation

**Fixes:**
1. Check CoreMotion permissions (Settings → Privacy → Motion)
2. Verify `tiltBiasScale` > 0 (increase to 50-80)
3. Test on physical device (not simulator)
4. Check MotionManager is receiving data (add debug prints)
5. Ensure `applyTilt` is being called from ContentView

---

### Issue: Shake Not Detected

**Symptoms:**
- Shaking device does nothing
- No waves from shake gesture

**Fixes:**
1. Increase shake detection threshold in MotionManager
2. Test with more vigorous shake
3. Check `shakeImpulseScale` > 0
4. Verify `shakeHandler` is connected in ContentView
5. Test on physical device (simulator won't have motion)

---

### Issue: Performance Below 60 FPS

**Symptoms:**
- Visible lag or stuttering
- Frame rate counter shows < 60 FPS
- Interaction feels slow

**Fixes:**
1. Reduce `maxParticles` → 100
2. Lower `foamIntensity` → 0 (disable foam)
3. Reduce `normalStrength` → 4.0
4. Consider lowering simulation resolution (512 → 256) in code
5. Test on newer device (A13+ recommended)

---

### Issue: Wakes Still Look Circular (Not Anisotropic)

**Symptoms:**
- Fast swipes produce circular ripples
- No elongated wake

**Fixes:**
1. Increase velocity threshold in `processCoalescedTouches` (currently 100)
2. Increase `anisotropyFactor` → 4.0
3. Increase `velocityScale` → 0.02
4. Verify `applyAnisotropicImpulse` is being called (add debug)
5. Swipe faster (need > 200 px/s)

---

### Issue: No Foam Visible

**Symptoms:**
- No white foam on waves
- Boundaries look plain

**Fixes:**
1. Increase `foamIntensity` → 0.8
2. Decrease `foamThreshold` → 0.03
3. Create stronger waves (higher `impulseStrength`)
4. Check foam texture is bound in renderer
5. Verify foam pipeline is created successfully

---

## Performance Profiling

### Using Xcode Instruments

1. **GPU Performance:**
   ```
   Product → Profile → Metal System Trace
   - Check GPU utilization (should be 10-20%)
   - Verify compute shader time (1-2ms)
   - Check fragment shader time (0.5-1ms)
   ```

2. **CPU Performance:**
   ```
   Product → Profile → Time Profiler
   - Touch processing: < 0.5ms
   - Particle update: < 0.3ms
   - Total per frame: < 1ms
   ```

3. **Memory:**
   ```
   Product → Profile → Leaks
   - No leaks should be detected
   - Memory usage: ~50-100 MB (constant)
   - Particle buffers created once, reused
   ```

### Expected Metrics (iPhone 13 Pro)

| Stage | Time Budget | Typical |
|-------|-------------|---------|
| Touch Processing | 0.5ms | 0.2ms |
| Compute Shaders | 2.5ms | 1.5ms |
| - Velocity Update | 0.8ms | 0.5ms |
| - Height Update | 0.6ms | 0.4ms |
| - Normals | 0.6ms | 0.4ms |
| - Foam | 0.5ms | 0.2ms |
| Fragment Shader | 1.5ms | 0.8ms |
| Particles | 0.5ms | 0.3ms |
| **Total** | **5ms** | **2.8ms** |
| **FPS** | **200+** | **~350** |

*Target: 60 FPS = 16.67ms budget; we have 13.87ms margin*

---

## Testing Checklist

Use this checklist before considering implementation complete:

### Functionality
- [ ] Gentle tilt creates sloshing
- [ ] Shake creates chaotic waves
- [ ] Slow touch creates circular wake
- [ ] Fast swipe creates anisotropic wake
- [ ] Multi-touch works without glitches
- [ ] Waves reflect at boundaries
- [ ] Particles spawn on strong impacts
- [ ] Particles create secondary ripples
- [ ] Foam appears on steep waves
- [ ] Foam appears at boundaries

### Visual Quality
- [ ] Water is blue (not gray)
- [ ] Specular highlights visible
- [ ] Background texture refracted
- [ ] Normals create 3D appearance
- [ ] Depth shading (shallow/deep)
- [ ] Rim lighting on edges
- [ ] Foam is white and clear

### Performance
- [ ] 60 FPS on iPhone 11+
- [ ] No stuttering or lag
- [ ] Smooth frame pacing
- [ ] No memory leaks
- [ ] No performance degradation over time

### Stability
- [ ] No crashes
- [ ] No NaN/Infinity values
- [ ] Simulation doesn't explode
- [ ] Particle limit enforced
- [ ] Works after 5+ minutes

### Configuration
- [ ] All sliders functional
- [ ] Real-time parameter updates
- [ ] Reset to defaults works
- [ ] Settings persist between sessions
- [ ] Values constrained to safe ranges

### Edge Cases
- [ ] Works with screen rotation
- [ ] Handles app backgrounding
- [ ] Recovers from memory warning
- [ ] Works with accessibility settings
- [ ] Handles device with no motion sensor

---

## Acceptance Criteria Summary

**The implementation is successful if:**

1. **Realism**: Water looks and behaves like real fluid in a container
2. **Motion Coupling**: Tilt and shake produce appropriate responses
3. **Touch Interaction**: Wakes are coherent, directional when appropriate
4. **Boundaries**: Waves reflect realistically, foam appears at edges
5. **Visual Quality**: Rendering is appealing with depth, lighting, refraction
6. **Performance**: Maintains 60 FPS on modern devices
7. **Stability**: No crashes, leaks, or degradation over time
8. **Configurability**: Extensive tuning options work as expected

**The user should feel like they are:**
- Looking down at water in a container
- Able to slosh it by tilting
- Able to create splashes by shaking
- Drawing finger through real water when touching

If these criteria are met, the implementation successfully delivers on the goal of realistic container-based water simulation.

---

**Version**: 3.0  
**Last Updated**: 2025-12-03  
**Test Environment**: iOS 15+, Metal-capable devices (A9+)

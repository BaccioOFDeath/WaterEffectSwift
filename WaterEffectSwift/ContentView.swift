// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var motionManager = MotionManager()
    @StateObject private var rippleEngine = RippleEngine()
    @State private var showSettings = false

    var body: some View {
#if os(iOS)
        ZStack {
            GeometryReader { geo in
                MetalRippleView(rippleEngine: rippleEngine)
                    .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    rippleEngine.addTouch(at: value.location, in: geo.size)
                                })
                    .onAppear {
                        motionManager.startUpdates(
                            handler: { motionData in
                                rippleEngine.applyTilt(gravity: motionData.gravity)
                            },
                            shakeHandler: { magnitude in
                                rippleEngine.handleShake(magnitude: magnitude)
                            }
                        )
                    }
                    .onDisappear {
                        motionManager.stopUpdates()
                    }
                    .ignoresSafeArea()
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
            
            if showSettings {
                SettingsView(config: $rippleEngine.config, isPresented: $showSettings)
            }
        }
#else
        Text("Water effect is only supported on iOS.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }
}

/// Configuration UI for water simulation parameters
struct SettingsView: View {
    @Binding var config: WaterSimConfig
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Physics")) {
                    VStack(alignment: .leading) {
                        Text("Damping: \(config.damping, specifier: "%.3f")")
                        Slider(value: $config.damping, in: 0.9...0.999)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Viscosity: \(config.viscosity, specifier: "%.4f")")
                        Slider(value: $config.viscosity, in: 0.0...0.02)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Wave Speed: \(config.waveSpeed, specifier: "%.2f")")
                        Slider(value: $config.waveSpeed, in: 0.5...2.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Boundary Damping: \(config.boundaryDamping, specifier: "%.2f")")
                        Slider(value: $config.boundaryDamping, in: 0.5...0.95)
                    }
                }
                
                Section(header: Text("Motion Response")) {
                    VStack(alignment: .leading) {
                        Text("Tilt Sensitivity: \(config.tiltBiasScale, specifier: "%.1f")")
                        Slider(value: $config.tiltBiasScale, in: 0...100)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Shake Intensity: \(config.shakeImpulseScale, specifier: "%.1f")")
                        Slider(value: $config.shakeImpulseScale, in: 0.5...5.0)
                    }
                }
                
                Section(header: Text("Touch Response")) {
                    VStack(alignment: .leading) {
                        Text("Impulse Strength: \(config.impulseStrength, specifier: "%.2f")")
                        Slider(value: $config.impulseStrength, in: 0.1...2.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Impulse Radius: \(config.impulseRadius, specifier: "%.0f")")
                        Slider(value: $config.impulseRadius, in: 5...50)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Velocity Scale: \(config.velocityScale, specifier: "%.3f")")
                        Slider(value: $config.velocityScale, in: 0.0...0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Wake Elongation: \(config.anisotropyFactor, specifier: "%.1f")")
                        Slider(value: $config.anisotropyFactor, in: 1.0...5.0)
                    }
                }
                
                Section(header: Text("Visual")) {
                    VStack(alignment: .leading) {
                        Text("Normal Strength: \(config.normalStrength, specifier: "%.1f")")
                        Slider(value: $config.normalStrength, in: 1.0...20.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Refraction: \(config.refractionScale, specifier: "%.3f")")
                        Slider(value: $config.refractionScale, in: 0.0...0.1)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Specular: \(config.specularStrength, specifier: "%.2f")")
                        Slider(value: $config.specularStrength, in: 0.0...2.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Fresnel: \(config.fresnelStrength, specifier: "%.2f")")
                        Slider(value: $config.fresnelStrength, in: 0.0...1.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Rim Light: \(config.rimLightIntensity, specifier: "%.2f")")
                        Slider(value: $config.rimLightIntensity, in: 0.0...1.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Foam Intensity: \(config.foamIntensity, specifier: "%.2f")")
                        Slider(value: $config.foamIntensity, in: 0.0...1.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Foam Threshold: \(config.foamThreshold, specifier: "%.3f")")
                        Slider(value: $config.foamThreshold, in: 0.01...0.2)
                    }
                }
                
                Section(header: Text("Particles")) {
                    VStack(alignment: .leading) {
                        Text("Splash Threshold: \(config.splashThreshold, specifier: "%.2f")")
                        Slider(value: $config.splashThreshold, in: 0.1...1.0)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Max Particles: \(config.maxParticles)")
                        Slider(value: Binding(
                            get: { Double(config.maxParticles) },
                            set: { config.maxParticles = Int($0) }
                        ), in: 50...500, step: 50)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Particle Feedback: \(config.particleFeedbackStrength, specifier: "%.2f")")
                        Slider(value: $config.particleFeedbackStrength, in: 0.0...1.0)
                    }
                }
                
                Section {
                    Button("Reset to Defaults") {
                        config = WaterSimConfig()
                    }
                }
            }
            .navigationTitle("Water Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }
}

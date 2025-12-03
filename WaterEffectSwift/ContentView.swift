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
                        motionManager.startUpdates { x, y in
                            rippleEngine.applyTilt(dx: x, dy: y)
                        }
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
                }
                
                Section(header: Text("Visual")) {
                    VStack(alignment: .leading) {
                        Text("Normal Strength: \(config.normalStrength, specifier: "%.1f")")
                        Slider(value: $config.normalStrength, in: 1.0...20.0)
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

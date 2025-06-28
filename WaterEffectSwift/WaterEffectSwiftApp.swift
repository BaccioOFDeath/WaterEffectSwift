//
//  WaterEffectSwiftApp.swift
//  WaterEffectSwift
//
//  Created by Garett Daly on 28/06/2025.
//

import SwiftUI

@main
struct WaterEffectSwiftApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

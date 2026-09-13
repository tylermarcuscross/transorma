//
//  transormaApp.swift
//  transorma
//
//  Created by Tyler Cross on 8/6/25.
//

import SwiftUI

@main
struct transormaApp: App {
    @StateObject private var model = ProtectionModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1040, height: 800)
    }
}

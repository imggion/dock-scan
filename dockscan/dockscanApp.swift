//
//  dockscanApp.swift
//  dockscan
//
//  Created by Giovanni D'Andrea on 17/12/25.
//

import SwiftUI

@main
struct dockscanApp: App {
    @StateObject private var dockerService = DockerService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dockerService)
        }
        .defaultSize(width: 1400, height: 860)

#if os(macOS)
        MenuBarExtra("Dockscan", systemImage: "cube.transparent") {
            MenuBarView()
                .environmentObject(dockerService)
        }
        .menuBarExtraStyle(.window)
#endif
    }
}

//
//  ContentView.swift
//  dockscan
//
//  Created by Giovanni D'Andrea on 17/12/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var dockerService: DockerService
    @State private var showingError = false

    var body: some View {
        DockscanHomeView()
        .task {
            await dockerService.resolveBackend()
        }
        .onChange(of: dockerService.errorMessage) { _, newValue in
            showingError = (newValue != nil)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { dockerService.clearError() }
        } message: {
            Text(dockerService.errorMessage ?? "")
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(DockerService())
    }
}
#endif

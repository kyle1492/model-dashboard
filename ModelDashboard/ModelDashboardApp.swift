import SwiftUI

@main
struct ModelDashboardApp: App {
    var body: some Scene {
        Window("Model Dashboard", id: "main") {
            DashboardView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

import SwiftUI

@main
struct RevIQApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var session = LiveSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.neonCyan)
        }
    }
}

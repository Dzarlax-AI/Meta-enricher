import SwiftUI

@main
struct MetaEnricherApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    ContentView()
                        .environment(appState)
                } else {
                    OnboardingView()
                        .environment(appState)
                }
            }
            .tint(Color.appAmber)
            .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

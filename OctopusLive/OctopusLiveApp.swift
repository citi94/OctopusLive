import SwiftUI
import WidgetKit

@main
struct OctopusLiveApp: App {
    init() {
        SharedConfig.clearOrphanedKeychainOnFreshInstall()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var isConfigured = SharedConfig.isConfigured
    // `-demo` launch argument opens straight into demo mode (screenshots, testing).
    @State private var isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    var body: some View {
        Group {
            if isConfigured || isDemo {
                NavigationStack {
                    LiveView(isDemo: isDemo)
                        // Fresh state when switching between demo and a real account,
                        // so demo numbers never linger on the live screen.
                        .id(isDemo)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView(onConnect: {
                                        isConfigured = true
                                        isDemo = false
                                    }, onDisconnect: {
                                        isConfigured = false
                                        isDemo = false
                                    })
                                } label: {
                                    Image(systemName: "gearshape")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                }
            } else {
                SettingsView(
                    onConnect: { isConfigured = true },
                    onDemo: { isDemo = true }
                )
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: isDemo, initial: true) { _, demo in
            guard SharedConfig.isDemo != demo else { return }
            SharedConfig.isDemo = demo
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

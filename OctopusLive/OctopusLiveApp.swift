import SwiftUI

@main
struct OctopusLiveApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var isConfigured = SharedConfig.isConfigured
    @State private var isDemo = false

    var body: some View {
        Group {
            if isConfigured || isDemo {
                NavigationStack {
                    LiveView(isDemo: isDemo)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView(onDisconnect: {
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
    }
}

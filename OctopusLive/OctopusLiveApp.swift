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

    var body: some View {
        Group {
            if isConfigured {
                NavigationStack {
                    LiveView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    SettingsView(onDisconnect: {
                                        isConfigured = false
                                    })
                                } label: {
                                    Image(systemName: "gearshape")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                }
            } else {
                SettingsView(onConnect: {
                    isConfigured = true
                })
            }
        }
        .preferredColorScheme(.dark)
    }
}

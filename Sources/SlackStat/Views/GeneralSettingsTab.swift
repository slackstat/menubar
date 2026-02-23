import ServiceManagement
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var store: StateStore
    let configManager: ConfigManager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert on failure
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Polling") {
                HStack {
                    Text("Poll interval:")
                    Slider(
                        value: Binding(
                            get: { Double(store.config.pollIntervalSeconds) },
                            set: { store.config.pollIntervalSeconds = Int($0) }
                        ), in: 10...120, step: 5)
                    Text("\(store.config.pollIntervalSeconds)s")
                        .frame(width: 40)
                }
            }

        }
        .padding()
        .onChange(of: store.config.pollIntervalSeconds) { _, _ in saveConfig() }
    }

    private func saveConfig() {
        try? configManager.save(store.config)
    }
}

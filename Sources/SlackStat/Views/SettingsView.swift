import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: StateStore
    let configManager: ConfigManager

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store, configManager: configManager)
                .tabItem { Label("General", systemImage: "gear") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 350)
    }
}

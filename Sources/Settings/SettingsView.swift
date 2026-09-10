import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppSettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }

            ConfigSettingsView()
                .tabItem { Label("Config", systemImage: "slider.horizontal.3") }

            Text("Conversion presets will be added with FFmpeg integration.")
                .tabItem { Label("Conversion", systemImage: "arrow.triangle.2.circlepath") }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }
}

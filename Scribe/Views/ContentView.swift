import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        #if os(iOS)
            TabView {
                Tab("Record", systemImage: "mic.fill") {
                    RecordTab()
                }

                Tab("Library", systemImage: "list.bullet") {
                    LibraryTab()
                }

                Tab("Settings", systemImage: "gearshape") {
                    SettingsTab()
                }
            }
        #else
            NavigationSplitView {
                LibraryTab()
            } detail: {
                Text("Select a recording")
                    .foregroundStyle(.secondary)
            }
        #endif
    }
}

import SwiftUI
import SwiftData

@main
struct ChiselApp: App {
    var body: some Scene {

        WindowGroup {
            MainNavigationContainerView()
        }
        .modelContainer(for: CompressionStat.self)
        #if os(macOS)
        .withMacOSCommands()
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
        }
        Window("About", id: "about") {
            AboutView()
        }
        #endif
    }
}

#if os(macOS)
extension Scene {
    func withMacOSCommands() -> some Scene {
        self
            .commands {
                CommandGroup(replacing: .appInfo) {
                    AboutMenuButton()
                }
            }
    }
}

struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Chisel") {
            openWindow(id: "about")
        }
    }
}
#endif

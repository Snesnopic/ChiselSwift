import SwiftUI

@main
struct ChiselApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 600, minHeight: 400)
                #endif
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

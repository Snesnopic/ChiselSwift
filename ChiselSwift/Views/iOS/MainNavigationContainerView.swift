import SwiftUI
import SwiftData

struct MainNavigationContainerView: View {
    var body: some View {
        TabView {
            CompressView()
                .tabItem {
                    Label("Compress", systemImage: "rectangle.compress.vertical")
                }
            
            StatsDashboardView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar.xaxis")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

        }
    }
}

#Preview("Light mode") {
    MainNavigationContainerView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    MainNavigationContainerView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

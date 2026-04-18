import SwiftUI
import SwiftData

struct AboutView: View {
    private let libraryVersion = "1.4.1"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var copyrightString: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "Copyright © 2026 Snesnopic"
    }
    var body: some View {
        VStack(spacing: 24) {

            AppIconView()
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)

            VStack(spacing: 4) {
                Text("Chisel")
                    .font(.system(size: 28, weight: .bold))

                Text("Version \(appVersion)")
                    .font(.body)
                Text("Chisel \(libraryVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Link("Chisel engine", destination: URL(string: "https://github.com/Snesnopic/chisel")!)
                Link("Chisel GUI", destination: URL(string: "https://github.com/Snesnopic/ChiselSwift")!)
                HStack(spacing: 0) {
                    Text("App icon by ")
                    Link("Mahary Esposito", destination: URL(string: "https://www.behance.net/mychan1")!)
                }
            }
            .font(.callout)
            .padding(.vertical, 8)

            Text(copyrightString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .navigationTitle("About")
        .padding(40)
        .frame(minWidth: 300, minHeight: 350)
    }
}

#Preview("Light mode") {
    AboutView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    AboutView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

import SwiftUI
import SwiftData

#if !os(macOS)
import UIKit
#endif

extension Bundle {
    var iconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }
}

struct AppIconView: View {
    var cornerRadius: CGFloat = 22

    var body: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
        #else
        Image(uiImage: UIImage(named: Bundle.main.iconFileName ?? "AppIcon")!)
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }
}

#Preview("Light mode") {
    AppIconView()
        .frame(width: 100, height: 100)
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    AppIconView()
        .frame(width: 100, height: 100)
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

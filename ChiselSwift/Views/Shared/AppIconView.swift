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
var view: Image {
#if os(macOS)
    return Image(nsImage: NSApplication.shared.applicationIconImage)
#else
    return Image(uiImage: UIImage(named: Bundle.main.iconFileName ?? "AppIcon")! )
#endif
}

func AppIconView() -> Image {
    return view
}
#Preview("Light mode") {
    AppIconView()
        .resizable()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    AppIconView()
        .resizable()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

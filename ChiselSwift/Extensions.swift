import Foundation
import SwiftUI

extension URL {
    var displayFolderName: String {
            if let localized = (try? self.resourceValues(forKeys: [.localizedNameKey]))?.localizedName {
                return localized
            }
            return self.lastPathComponent
        }

    var userFriendlyPath: String {
            #if os(macOS)
            return self.path
            #else
            let components = self.pathComponents
            var pathNodes: [String] = []

            if let cloudIndex = components.firstIndex(of: "com~apple~CloudDocs") {
                pathNodes.append("iCloud Drive")
                pathNodes.append(contentsOf: components.dropFirst(cloudIndex + 1))
            } else if let fpIndex = components.firstIndex(of: "File Provider Storage") {
                pathNodes.append(String(localized: "On My iPhone"))
                pathNodes.append(contentsOf: components.dropFirst(fpIndex + 1))
            } else if let docsIndex = components.firstIndex(of: "Documents") {
                pathNodes.append(String(localized: "Documents"))
                pathNodes.append(contentsOf: components.dropFirst(docsIndex + 1))
            } else {
                let hiddenSystemFolders = ["/", "private", "var", "mobile", "Containers", "Data", "Application", "Shared", "AppGroup"]
                let visibleComponents = components.filter { !hiddenSystemFolders.contains($0) }

                let cleaned = visibleComponents.filter { $0.count != 36 }

                if cleaned.isEmpty {
                    pathNodes.append(self.displayFolderName)
                } else {
                    pathNodes.append(contentsOf: cleaned)
                }
            }
            if pathNodes.count > 1 {
                pathNodes[pathNodes.count - 1] = self.displayFolderName
            }

            return pathNodes.joined(separator: " ▹ ")
            #endif
        }
}
extension View {
    @ViewBuilder func `if`<T>(_ condition: Bool, transform: (Self) -> T) -> some View where T: View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension Binding where Value == Int {
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(self.wrappedValue) },
            set: { self.wrappedValue = Int($0) }
        )
    }
}
// utility to format byte counts natively
extension Int64 {
    func formatBytes() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

#if !os(macOS)
extension UIDevice {
    static var isIpad: Bool {
        current.userInterfaceIdiom == .pad
    }
}
#endif

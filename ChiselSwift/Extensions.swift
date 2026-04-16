import Foundation
import SwiftUI

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

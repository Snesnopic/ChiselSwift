import Foundation

enum OutputMode: String, CaseIterable, Identifiable {
    case overwrite = "Overwrite"
    case sideBySide = "Side-by-side (a-compressed.pdf)"
    case keepOriginal = "Keep original (a-original.pdf)"
    #if os(macOS)
    case outputFolder = "Custom output folder"
    #endif
    var id: String { self.rawValue }
}

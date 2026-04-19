import Foundation

enum OutputMode: String, CaseIterable, Identifiable {
    case overwrite = "overwrite"
    case sideBySide = "sideBySide"
    case keepOriginal = "keepOriginal"
    #if os(macOS)
    case outputFolder = "outputFolder"
    #endif

    var id: String { rawValue }

    // Localized, user-facing title for each mode
    var title: String {
        switch self {
        case .overwrite:
            return String(localized: "Overwrite")
        case .sideBySide:
            return String(localized: "Alongside original (a-compressed.pdf)")
        case .keepOriginal:
            return String(localized: "Rename original (a-original.pdf)")
        #if os(macOS)
        case .outputFolder:
            return String(localized: "Custom output folder")
        #endif
        }
    }
}

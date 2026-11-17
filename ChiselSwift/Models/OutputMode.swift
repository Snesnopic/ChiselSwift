import Foundation

/// Determines how the compressed files are saved relative to their originals.
enum OutputMode: String, CaseIterable, Identifiable {
    /// The original file is overwritten by the compressed version.
    case overwrite

    /// The compressed file is saved next to the original, with a suffix (e.g. -compressed).
    case sideBySide

    /// The original file is renamed to a backup (e.g. -original), and the compressed file takes its place.
    case keepOriginal

    /// The compressed file is placed into a user-specified custom directory.
    case outputFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overwrite:
            return String(localized: "Overwrite")
        case .sideBySide:
            return String(localized: "Alongside original (a.compressed.pdf)")
        case .keepOriginal:
            return String(localized: "Rename original (a.original.pdf)")
        case .outputFolder:
            return String(localized: "Custom output folder")
        }
    }
}

import Foundation

/// Determines how the compressed files are saved relative to their originals.
enum OutputMode: String, CaseIterable, Identifiable {
    /// The original file is overwritten by the compressed version.
    case overwrite

    /// The compressed file is saved next to the original, with a suffix (e.g. .compressed).
    case sideBySide

    /// The original file is renamed to a backup (e.g. .original), and the compressed file takes its place.
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

    /// Moves `compressed` where this mode puts the result for `original`, and returns its new location.
    nonisolated func place(_ compressed: URL, for original: URL, outputFolder: URL?) throws -> URL {
        let fm = FileManager.default
        let originalNoExt = original.deletingPathExtension()
        let ext = original.pathExtension

        // start access to the original resource (held by the bookmark/active access)
        guard original.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "ChiselError", code: 1, userInfo: [NSLocalizedDescriptionKey: "PERMISSION DENIED FOR ORIGINAL FILE"])
        }
        defer { original.stopAccessingSecurityScopedResource() }

        switch self {
        case .overwrite:
            print("OVERWRITING ORIGINAL: \(original.lastPathComponent)")
            return try fm.replaceItemAt(original, withItemAt: compressed) ?? original

        case .sideBySide:
            let newURL = Self.uniqueURL(for: originalNoExt.appendingPathExtension("compressed").appendingPathExtension(ext))
            print("SAVING SIDE-BY-SIDE: \(newURL.lastPathComponent)")
            try fm.moveItem(at: compressed, to: newURL)
            return newURL

        case .keepOriginal:
            let backupURL = Self.uniqueURL(for: originalNoExt.appendingPathExtension("original").appendingPathExtension(ext))
            print("CREATING BACKUP AND SWAPPING: \(backupURL.lastPathComponent)")
            try fm.moveItem(at: original, to: backupURL)
            try fm.moveItem(at: compressed, to: original)
            return original

        case .outputFolder:
            guard let outputFolder else {
                throw NSError(domain: "ChiselError", code: 2, userInfo: [NSLocalizedDescriptionKey: "NO OUTPUT FOLDER SELECTED"])
            }
            guard outputFolder.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "ChiselError", code: 3, userInfo: [NSLocalizedDescriptionKey: "PERMISSION DENIED FOR OUTPUT FOLDER"])
            }
            defer { outputFolder.stopAccessingSecurityScopedResource() }

            let destURL = Self.uniqueURL(for: outputFolder.appendingPathComponent(original.lastPathComponent))
            print("MOVING TO CUSTOM FOLDER: \(destURL.path)")
            try fm.moveItem(at: compressed, to: destURL)
            return destURL
        }
    }

    /// Resolves the output folder bookmark saved by the settings.
    nonisolated static func resolveOutputFolder(from bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            let url = try URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        } catch {
            print("ERROR RESOLVING BOOKMARK: \(error)")
            return nil
        }
    }

    nonisolated private static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent

        var counter = 1
        var newURL = url
        while fm.fileExists(atPath: newURL.path) {
            newURL = dir.appendingPathComponent("\(name)-\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return newURL
    }
}

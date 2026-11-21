import Foundation
import UniformTypeIdentifiers

/// Represents a file enqueued for processing.
/// This structure tracks the file's state, size, and nested children if it's a container.
struct FileItem: Identifiable, Equatable {
    let id = UUID()

    /// The original location of the file.
    var url: URL

    /// The temporary working copy used during compression.
    var tempURL: URL

    /// Current processing status.
    var status: ProcessingStatus

    /// Original file size in bytes.
    var size: Int64

    /// Compressed file size in bytes, if applicable.
    var sizeAfter: Int64?

    /// The file extension in lowercase.
    var originalExtension: String

    /// Nested files if the current file is a container format.
    var children: [FileItem]?

    /// Processing logs associated with this file.
    var logs: [String] = []

    // localized reason chisel left it as it was, when the user can do something about it
    var skipNote: String?

    var savingPercentage: Double? {
            guard let sizeAfter = sizeAfter, size > 0 else { return nil }
            let gain = Double(size - sizeAfter)
            return (gain / Double(size)) * 100
        }

    /// The processing lifecycle status of a file.
    enum ProcessingStatus: Equatable {
        case pending
        case processing
        case noGain
        case skipped
        case completed(URL)
        case simulated
        case error(String)
        case stopped
    }

    /// Derives the appropriate SF Symbol based on the file extension.
    var typeIconName: String {
            return FileCategory.category(for: originalExtension).iconName
        }

    /// The best URL to preview this file's current content, if any.
    /// Prefers the original location (finalizing leaves it valid, whichever mode is
    /// used), falling back to the temporary working copy when that's all that exists
    /// (mid-processing, or an extracted child whose container was never reassembled).
    var previewURL: URL? {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            if FileManager.default.fileExists(atPath: tempURL.path) {
                return tempURL
            }
            return nil
        }
}

/// A high-level categorization of file formats used for UI representation.
enum FileCategory {
    case image
    case audio
    case video
    case document
    case archive
    case font
    case scientific
    case database
    case unknown
}

extension FileCategory {
    var displayName: String {
        switch self {
        case .image: return String(localized: "Image")
        case .audio: return String(localized: "Audio")
        case .video: return String(localized: "Video")
        case .document: return String(localized: "Document")
        case .archive: return String(localized: "Archive")
        case .font: return String(localized: "Font")
        case .scientific: return String(localized: "Scientific")
        case .database: return String(localized: "Database")
        case .unknown: return String(localized: "Unknown")
        }
    }
    // map engine category to sf symbol
    var iconName: String {
        switch self {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .document: return "doc.richtext"
        case .archive: return "doc.zipper"
        case .font: return "textformat"
        case .scientific: return "flask"
        case .database: return "cylinder.split.1x2"
        case .unknown: return "doc"
        }
    }
    static func category(for ext: String) -> FileCategory {
            // Rimuoviamo il punto iniziale se presente e uniformiamo in minuscolo
            let cleanExt = ext.hasPrefix(".") ? String(ext.dropFirst()).lowercased() : ext.lowercased()

            switch cleanExt {

            // MARK: - Images
            case "jpg", "jpeg", "jpe", "jif", "jfif", "jfi", "thm", "png", "apng", "gif", "webp", "jxl", "tif", "tiff", "tga", "targa", "icb", "vda", "vst", "bmp", "dib", "ico", "cur", "icns", "gft", "pnm", "ppm", "pgm", "pbm", "jp2", "j2k", "j2c", "mng", "jng", "pcx", "dcx", "pcc", "ora", "svg", "psd", "psb":
                return .image

            // MARK: - Audio
            case "mp3", "m4a", "m4b", "wav", "flac", "ogg", "oga", "opus", "aif", "aiff", "aifc", "ape", "wv", "wvc", "wvp", "dsf", "dff", "mpc", "mp+", "tta":
                return .audio

            // MARK: - Video
            case "mp4", "m4v", "mov", "qt", "3gp", "3g2", "mkv", "mka", "webm", "wma", "wmv", "asf", "swf", "avi", "ogv", "ogx":
                return .video

            // MARK: - Documents
            case "pdf", "xml", "xhtml", "kml", "gpx", "dae", "rss", "atom", "xmp", "xsl", "xslt", "json", "docx", "docm", "dotm", "dotx", "xlsx", "xlsm", "xltm", "xltx", "pptx", "pptm", "potm", "potx", "ppsm", "ppsx", "doc", "xls", "ppt", "msi", "msp", "mst", "pub", "vsd", "vss", "adp", "mdb", "mdt", "mpd", "mpp", "mpt", "rvt", "sldasm", "slddrw", "sldprt", "snt", "spl", "dot", "xlt", "pps", "chm", "fla", "one", "ost", "rfa", "rte", "wps", "odt", "ods", "odp", "odg", "odf", "odb", "epub", "fb2", "cbz", "cbt", "vcf", "xps", "oxps", "exe", "dll", "ocx", "scr", "cpl", "sys", "drv", "bpl", "icl", "rll", "vbx", "dwfx", "3mf", "kmz", "xlam", "lua", "luac", "stl", "eml", "emlx", "msg", "mht", "mhtml", "mbx", "html", "htm", "css", "md", "markdown", "vcard", "xlsb", "ppam", "sldm", "thmx", "vsdx", "vsdm", "vssx", "vssm", "vstx", "vstm":
                return .document

            // MARK: - Archives
            case "zip", "air", "bsz", "cdr", "csl", "gallery", "gallerycollection", "galleryitem", "grs", "ita", "itz", "nbk", "notebook", "oex", "osk", "pk3", "puz", "stz", "vlt", "wal", "wba", "wmz", "wsz", "xap", "xl", "xmz", "xsn", "appx", "bar", "dwf", "easm", "rmskin", "sldx", "zipx", "tar", "gz", "tgz", "deb", "ipk", "svgz", "bz2", "xz", "lzma", "iso", "cpio", "a", "ar", "lib", "br", "zst", "tzst", "jar", "xpi", "apk", "ipa", "ipsw", "vsix", "nupkg", "war", "ear", "aab", "rdb", "knz", "cab", "lz4", "emz", "7z", "cb7":
                return .archive

            // MARK: - Fonts
            case "woff", "woff2":
                return .font

            // MARK: - Scientific
            case "mseed", "mseed2", "mseed3":
                return .scientific

            // MARK: - Databases
            case "sqlite", "sqlite3", "db", "thumbs.db":
                return .database

            default:
                return .unknown
            }
        }
}

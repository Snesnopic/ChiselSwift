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
        case error(String)
        case stopped
    }

    /// Derives the appropriate SF Symbol based on the file extension.
    var typeIconName: String {
            return FileCategory.category(for: originalExtension).iconName
        }

    /// Checks if the temporary working copy is available for preview.
    var isPreviewAvailable: Bool {
            FileManager.default.fileExists(atPath: tempURL.path)
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
            case "jpg", "jpeg", "jpe", "jif", "jfif", "jfi", "thm", "png", "apng", "gif", "webp", "jxl", "tif", "tiff", "tga", "targa", "icb", "vda", "vst", "bmp", "dib", "ico", "cur", "icns", "gft", "pnm", "ppm", "pgm", "jp2", "j2k", "j2c", "mng", "jng", "pcx", "dcx", "pcc", "ora", "svg":
                return .image

            // MARK: - Audio
            case "mp3", "m4a", "m4b", "wav", "flac", "ogg", "oga", "opus", "aif", "aiff", "aifc", "ape", "wv", "wvc", "wvp", "dsf", "dff", "mpc", "mp+", "tta":
                return .audio

            // MARK: - Video
            case "mp4", "m4v", "mov", "qt", "3gp", "3g2", "mkv", "mka", "webm", "wma", "wmv", "asf", "swf":
                return .video

            // MARK: - Documents
            case "pdf", "xml", "xhtml", "kml", "gpx", "dae", "rss", "atom", "xmp", "xsl", "xslt", "json", "docx", "docm", "dotm", "dotx", "xlsx", "xlsm", "xltm", "xltx", "pptx", "pptm", "potm", "potx", "ppsm", "ppsx", "doc", "xls", "ppt", "msi", "msp", "mst", "pub", "vsd", "vss", "adp", "mdb", "mdt", "mpd", "mpp", "mpt", "rvt", "sldasm", "slddrw", "sldprt", "snt", "spl", "dot", "xlt", "pps", "chm", "fla", "one", "ost", "rfa", "rte", "wps", "odt", "ods", "odp", "odg", "odf", "odb", "epub", "fb2", "cbz", "cbt", "vcf", "xps", "oxps", "exe", "dll", "ocx", "scr", "cpl", "sys", "drv", "bpl", "icl", "rll", "vbx", "dwfx", "3mf", "kmz", "xlam":
                return .document

            // MARK: - Archives
            case "zip", "air", "bsz", "cdr", "csl", "gallery", "gallerycollection", "galleryitem", "grs", "ita", "itz", "nbk", "notebook", "oex", "osk", "pk3", "puz", "stz", "vlt", "wal", "wba", "wmz", "wsz", "xap", "xl", "xmz", "xsn", "appx", "bar", "dwf", "easm", "rmskin", "sldx", "zipx", "tar", "gz", "tgz", "deb", "ipk", "svgz", "bz2", "xz", "lzma", "iso", "cpio", "a", "ar", "lib", "br", "zst", "tzst", "jar", "xpi", "apk", "ipa", "ipsw", "vsix", "nupkg", "war", "ear", "aab", "rdb", "knz":
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

enum FileType: String {
    // Images
    case jpeg, gif, jxl, webp, png, tiff, tga, bmp, ico, icns, gft, pnm, ora, svg

    // Documents
    case xml, pdf, docx, xlsx, pptx, cfbf, odt, epub, fb2, cbz, xps, dwfx, mf3, kmz

    // Audio
    case flac, ogg, opus, mp3, m4a, wav, aiff, ape, wavpack, dsf, dff, mpc, tta

    // Video
    case mkv, wma, swf

    // Archives
    case br, zip, tar, gzip, bzip2, xz, lzma, iso, cpio, ar, zstd, jar, xpi, apk, vsix, war, aab, rdb

    // Fonts
    case woff, woff2

    // Scientific
    case mseed

    // Databases
    case sqlite

    case unknown
}

let fileTypeToCategory: [FileType: FileCategory] = [
    // Images
    .jpeg: .image, .gif: .image, .jxl: .image, .webp: .image, .png: .image,
    .tiff: .image, .tga: .image, .bmp: .image, .ico: .image, .icns: .image,
    .gft: .image, .pnm: .image, .ora: .image, .svg: .image,

    // Documents
    .xml: .document, .pdf: .document, .docx: .document, .xlsx: .document,
    .pptx: .document, .cfbf: .document, .odt: .document, .epub: .document,
    .fb2: .document, .cbz: .document, .xps: .document, .dwfx: .document,
    .mf3: .document, .kmz: .document,

    // Audio
    .flac: .audio, .ogg: .audio, .opus: .audio, .mp3: .audio, .m4a: .audio,
    .wav: .audio, .aiff: .audio, .ape: .audio, .wavpack: .audio,
    .dsf: .audio, .dff: .audio, .mpc: .audio, .tta: .audio,

    // Video
    .mkv: .video, .wma: .video, .swf: .video,

    // Archives
    .br: .archive, .zip: .archive, .tar: .archive, .gzip: .archive,
    .bzip2: .archive, .xz: .archive, .lzma: .archive, .iso: .archive,
    .cpio: .archive, .ar: .archive, .zstd: .archive, .jar: .archive,
    .xpi: .archive, .apk: .archive, .vsix: .archive, .war: .archive,
    .aab: .archive, .rdb: .archive,

    // Fonts
    .woff: .font, .woff2: .font,

    // Scientific
    .mseed: .scientific,

    // Databases
    .sqlite: .database
]

let mimeToTypeMap: [String: FileType] = {
    var map: [String: FileType] = [:]

    map.merge(imageMimeMap) { $1 }
    map.merge(documentMimeMap) { $1 }
    map.merge(audioMimeMap) { $1 }
    map.merge(videoMimeMap) { $1 }
    map.merge(archiveMimeMap) { $1 }
    map.merge(fontMimeMap) { $1 }
    map.merge(scientificMimeMap) { $1 }
    map.merge(databaseMimeMap) { $1 }

    return map
}()

let imageMimeMap: [String: FileType] = [
    "image/jpeg": .jpeg,
    "image/jpg": .jpeg,
    "image/gif": .gif,
    "image/jxl": .jxl,
    "image/webp": .webp,
    "image/x-webp": .webp,
    "image/png": .png,
    "image/tiff": .tiff,
    "image/tiff-fx": .tiff,
    "image/x-tga": .tga,
    "image/tga": .tga,
    "image/bmp": .bmp,
    "image/x-ms-bmp": .bmp,
    "image/x-icon": .ico,
    "image/vnd.microsoft.icon": .ico,
    "image/x-icns": .icns,
    "application/x-gft": .gft,
    "image/x-portable-anymap": .pnm,
    "image/x-portable-pixmap": .pnm,
    "image/openraster": .ora,
    "image/svg+xml": .svg
]
let documentMimeMap: [String: FileType] = [
    "application/xml": .xml,
    "text/xml": .xml,
    "application/xhtml+xml": .xml,
    "application/vnd.google-earth.kml+xml": .xml,
    "application/gpx+xml": .xml,
    "model/vnd.collada+xml": .xml,
    "application/rss+xml": .xml,
    "application/atom+xml": .xml,
    "application/rdf+xml": .xml,

    "application/pdf": .pdf,

    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": .docx,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": .xlsx,
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": .pptx,

    "application/x-ole-storage": .cfbf,
    "application/msword": .cfbf,
    "application/vnd.ms-excel": .cfbf,
    "application/vnd.ms-powerpoint": .cfbf,
    "application/x-msi": .cfbf,

    "application/vnd.oasis.opendocument.text": .odt,
    "application/vnd.oasis.opendocument.spreadsheet": .odt,
    "application/vnd.oasis.opendocument.presentation": .odt,
    "application/vnd.oasis.opendocument.graphics": .odt,
    "application/vnd.oasis.opendocument.formula": .odt,

    "application/epub+zip": .epub,
    "application/x-fictionbook+xml": .fb2,

    "application/vnd.comicbook+zip": .cbz,
    "application/vnd.comicbook+tar": .cbz,

    "application/vnd.ms-xpsdocument": .xps,
    "application/oxps": .xps,

    "model/vnd.dwfx+xps": .dwfx,

    "application/vnd.ms-package": .mf3,
    "application/vnd.google-earth.kmz": .kmz
]
let audioMimeMap: [String: FileType] = [
    "audio/flac": .flac,
    "audio/x-flac": .flac,

    "audio/ogg": .ogg,
    "audio/oga": .ogg,

    "audio/vorbis": .opus,
    "audio/opus": .opus,

    "audio/mpeg": .mp3,

    "audio/mp4": .m4a,
    "audio/x-m4a": .m4a,
    "video/mp4": .m4a,

    "audio/wav": .wav,
    "audio/x-wav": .wav,

    "audio/aiff": .aiff,
    "audio/x-aiff": .aiff,

    "audio/ape": .ape,
    "audio/x-ape": .ape,

    "audio/x-wavpack": .wavpack,
    "audio/x-wavpack-correction": .wavpack,

    "audio/dsf": .dsf,
    "audio/x-dsf": .dsf,

    "audio/dff": .dff,
    "audio/x-dff": .dff,

    "audio/musepack": .mpc,
    "audio/x-musepack": .mpc,

    "audio/tta": .tta,
    "audio/x-tta": .tta
]
let videoMimeMap: [String: FileType] = [
    "video/x-matroska": .mkv,
    "audio/x-matroska": .mkv,
    "video/webm": .mkv,
    "audio/webm": .mkv,

    "audio/x-ms-wma": .wma,
    "video/x-ms-wmv": .wma,
    "video/x-ms-asf": .wma,

    "application/x-shockwave-flash": .swf
]
let archiveMimeMap: [String: FileType] = [
    "application/x-brotli": .br,
    "application/brotli": .br,

    "application/zip": .zip,
    "application/x-zip-compressed": .zip,

    "application/x-tar": .tar,

    "application/gzip": .gzip,

    "application/x-bzip2": .bzip2,

    "application/x-xz": .xz,

    "application/x-lzma": .lzma,

    "application/x-iso9660-image": .iso,

    "application/x-cpio": .cpio,

    "application/x-archive": .ar,

    "application/zstd": .zstd,
    "application/x-zstd": .zstd,

    "application/java-archive": .jar,

    "application/x-xpinstall": .xpi,

    "application/vnd.android.package-archive": .apk,

    "application/x-rdb": .rdb
]
let fontMimeMap: [String: FileType] = [
    "font/woff": .woff,
    "font/woff2": .woff2
]
let scientificMimeMap: [String: FileType] = [
    "application/vnd.fdsn.mseed": .mseed
]
let databaseMimeMap: [String: FileType] = [
    "application/x-sqlite3": .sqlite,
    "application/vnd.sqlite3": .sqlite
]
func mimeToFileType(_ mime: String) -> FileType {
    mimeToTypeMap[mime] ?? .unknown
}

func fileTypeToCategory(_ type: FileType) -> FileCategory {
    fileTypeToCategory[type] ?? .unknown
}
func mimeToCategory(_ mime: String) -> FileCategory {
    let type = mimeToFileType(mime)
    return fileTypeToCategory(type)
}

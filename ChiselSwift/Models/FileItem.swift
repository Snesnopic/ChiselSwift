import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var tempURL: URL
    var status: ProcessingStatus
    var size: Int64
    var sizeAfter: Int64?
    var originalExtension: String
    var children: [FileItem]?
    var logs: [String] = []

    var savingPercentage: Double? {
            guard let sizeAfter = sizeAfter, size > 0 else { return nil }
            let gain = Double(size - sizeAfter)
            return (gain / Double(size)) * 100
        }

    enum ProcessingStatus: Equatable {
        case pending
        case processing
        case noGain
        case skipped
        case completed(URL)
        case error(String)
        case stopped
    }

    var typeIconName: String {
            let ext = originalExtension.lowercased()

            // 1. fast path: direct extension to filetype matching
            if let type = FileType(rawValue: ext) {
                return fileTypeToCategory[type]?.iconName ?? "doc"
            }

            // 2. fallback: system mime type resolution
            if let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType {
                return mimeToCategory(mimeType).iconName
            }

            // 3. absolute fallback
            return "doc"
        }
}

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

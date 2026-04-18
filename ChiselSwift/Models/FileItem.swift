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

    // resolve type dynamically using uttype
    var typeIconName: String {
        guard let utType = UTType(filenameExtension: originalExtension) else {
            return "doc"
        }

        if utType.conforms(to: .image) { return "photo" }
        if utType.conforms(to: .audiovisualContent) { return "film" }
        if utType.conforms(to: .audio) { return "waveform" }
        if utType.conforms(to: .archive) { return "doc.zipper" }
        if utType.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if utType.conforms(to: .text) { return "doc.text" }
        if utType.conforms(to: .pdf) { return "doc.richtext" }

        return "doc"
    }
}

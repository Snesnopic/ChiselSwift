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

extension FileItem {
    // generates heterogeneous dummy data covering all statuses and edge cases
    static var mockData: [FileItem] {
        [
            // completed with significant savings
            FileItem(
                url: URL(fileURLWithPath: "/Users/dev/Pictures/architecture.jpg"),
                tempURL: URL(fileURLWithPath: "/tmp/chisel/architecture.jpg"),
                status: .completed(URL(fileURLWithPath: "/Users/dev/Pictures/architecture_compressed.jpg")),
                size: 8_500_000,
                sizeAfter: 2_100_000,
                originalExtension: "jpg",
                logs: [
                    "STARTED PROCESSING architecture.jpg",
                    "OPTIMIZING JPEG HUFFMAN TABLES",
                    "COMPLETED: SAVED 6.4 MB"
                ]
            ),

            // processing a large video
            FileItem(
                url: URL(fileURLWithPath: "/Users/dev/Movies/render_v2.mkv"),
                tempURL: URL(fileURLWithPath: "/tmp/chisel/render_v2.mkv"),
                status: .processing,
                size: 4_200_000_000,
                sizeAfter: nil,
                originalExtension: "mkv",
                logs: [
                    "INITIALIZING DEMUXER",
                    "EXTRACTING STREAMS",
                    "ENCODING HEVC VIDEO STREAM (PASS 1)..."
                ]
            ),

            // error state due to corruption
            FileItem(
                url: URL(fileURLWithPath: "/Users/dev/Downloads/dataset.zip"),
                tempURL: URL(fileURLWithPath: "/tmp/chisel/dataset.zip"),
                status: .error("CRC mismatch in central directory"),
                size: 450_000_000,
                sizeAfter: nil,
                originalExtension: "zip",
                logs: [
                    "READING ZIP HEADERS",
                    "ERROR: CRC MISMATCH DETECTED. FILE MAY BE CORRUPTED."
                ]
            ),

            // compression yielded no gain
            FileItem(
                url: URL(fileURLWithPath: "/Users/dev/Music/lossless_track.flac"),
                tempURL: URL(fileURLWithPath: "/tmp/chisel/lossless_track.flac"),
                status: .noGain,
                size: 42_000_000,
                sizeAfter: 42_050_000,
                originalExtension: "flac",
                logs: [
                    "ANALYZING AUDIO SPECTRUM",
                    "ATTEMPTING RE-COMPRESSION",
                    "OUTPUT LARGER THAN INPUT. ABORTING AND KEEPING ORIGINAL."
                ]
            ),

            // stopped by user
            FileItem(
                url: URL(fileURLWithPath: "/Users/dev/Documents/thesis.pdf"),
                tempURL: URL(fileURLWithPath: "/tmp/chisel/thesis.pdf"),
                status: .stopped,
                size: 15_000_000,
                sizeAfter: nil,
                originalExtension: "pdf",
                logs: [
                    "PARSING PDF OBJECTS",
                    "DOWNSAMPLING IMAGES",
                    "PROCESS INTERRUPTED BY USER."
                ]
            ),

            // item with nested children (e.g., an uncompressed archive or directory)
            FileItem(
                url: URL(fileURLWithPath: "/Users/dev/Projects/engine_core"),
                tempURL: URL(fileURLWithPath: "/tmp/chisel/engine_core"),
                status: .pending,
                size: 85_000,
                sizeAfter: nil,
                originalExtension: "",
                children: [
                    FileItem(
                        url: URL(fileURLWithPath: "/Users/dev/Projects/engine_core/main.cpp"),
                        tempURL: URL(fileURLWithPath: "/tmp/chisel/engine_core/main.cpp"),
                        status: .pending,
                        size: 25_000,
                        sizeAfter: nil,
                        originalExtension: "cpp"
                    ),
                    FileItem(
                        url: URL(fileURLWithPath: "/Users/dev/Projects/engine_core/memory_pool.h"),
                        tempURL: URL(fileURLWithPath: "/tmp/chisel/engine_core/memory_pool.h"),
                        status: .pending,
                        size: 60_000,
                        sizeAfter: nil,
                        originalExtension: "h"
                    )
                ],
                logs: [
                    "QUEUED DIRECTORY FOR BATCH COMPRESSION"
                ]
            )
        ]
    }
}

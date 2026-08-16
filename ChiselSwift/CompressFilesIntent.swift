import AppIntents
import ChiselKit
import SwiftData
import Foundation

/// An App Intent that exposes Chisel's compression capabilities to Apple Shortcuts and Siri.
/// This allows users to compress files directly from the Finder context menu or automated workflows.
struct CompressFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Compress with Chisel"
    static let description = IntentDescription("Compresses the provided files using the Chisel engine.")

    /// The list of files provided by the user or the shortcut input.
    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.item"])
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Compress \(\.$files)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let startTime = Date()
        #if os(macOS)
        // show spinner on main thread
        await MenuBarProgressManager.shared.show()

        // ensure cleanup always happens, even if errors are thrown
        defer {
            Task {
                await MenuBarProgressManager.shared.hide()
            }
        }
        #endif
        // 1. read preferences matching @appstorage keys
        let defaults = UserDefaults.standard
        let iterations = UInt32(defaults.integer(forKey: "iterations") == 0 ? 15 : defaults.integer(forKey: "iterations"))
        let iterationsLarge = UInt32(defaults.integer(forKey: "iterationsLarge") == 0 ? 5 : defaults.integer(forKey: "iterationsLarge"))
        let threads = UInt32(defaults.integer(forKey: "threads") == 0 ? 4 : defaults.integer(forKey: "threads"))

        // 2. setup isolated swiftdata context
        let container = try ModelContainer(for: CompressionStat.self)
        let context = ModelContext(container)

        // 3. setup chisel engine
        let chisel = Chisel()
        await chisel.configure(
            iterations: iterations,
            iterationsLarge: iterationsLarge,
            preserveMetadata: true,
            verifyChecksums: false,
            threads: threads,
            outputDirectory: nil
        )

        // 4. safely copy shortcut files to temp directory
        let tempDirectory = FileManager.default.temporaryDirectory
        var workingUrls: [URL] = []

        for intentFile in files {
            guard let originalURL = intentFile.fileURL else { continue }
            // Use a unique UUID folder to prevent name collisions if multiple files have the same name
            let uniqueFolder = tempDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: uniqueFolder, withIntermediateDirectories: true)
            let destURL = uniqueFolder.appendingPathComponent(originalURL.lastPathComponent)

            try? FileManager.default.copyItem(at: originalURL, to: destURL)
            workingUrls.append(destURL)
        }

        // 5. execute processing
        var outputFiles: [IntentFile] = []

        let stream = await chisel.process(files: workingUrls)
        for await event in stream {
            switch event {
            case .finish(let path, let before, let after, _, _, _):
                let url = URL(fileURLWithPath: path)

                // only export and track the root requested files, ignoring internal extracted files
                if workingUrls.contains(where: { $0.path == url.path }) {
                    outputFiles.append(IntentFile(fileURL: url))

                    let duration = Date().timeIntervalSince(startTime)
                    let stat = CompressionStat(
                        fileExtension: url.pathExtension,
                        originalSize: Int64(before),
                        compressedSize: Int64(after),
                        durationSeconds: duration
                    )
                    context.insert(stat)
                }
            default:
                break
            }
        }

        try context.save()

        // returning output files allows chaining actions in the shortcut app
        return .result(value: outputFiles)
    }
}

struct ChiselShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompressFilesIntent(),
            phrases: [
                "Compress files with \(.applicationName)",
                "Run \(.applicationName)",
                "Squeeze files using \(.applicationName)"
            ],
            shortTitle: "Compress files",
            systemImageName: "rectangle.compress.vertical"
        )
    }
}

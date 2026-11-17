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
        let preserveMetadata = defaults.object(forKey: "preserveMetadata") as? Bool ?? true
        let verifyChecksums = defaults.bool(forKey: "verifyChecksums")
        let breakSignatures = defaults.bool(forKey: "breakSignatures")

        // 2. setup isolated swiftdata context
        let container = try ModelContainer(for: CompressionStat.self)
        let context = ModelContext(container)

        // 3. setup chisel engine
        let chisel = Chisel()
        await chisel.configure(
            iterations: iterations,
            iterationsLarge: iterationsLarge,
            preserveMetadata: preserveMetadata,
            verifyChecksums: verifyChecksums,
            breakSignatures: breakSignatures,
            threads: threads,
            outputDirectory: nil
        )

        // 4. safely copy shortcut files to temp directory; a file without a working copy is passed through as it came
        let tempDirectory = FileManager.default.temporaryDirectory
        var jobs: [(input: IntentFile, workingCopy: URL?)] = []

        for intentFile in files {
            // Use a unique UUID folder to prevent name collisions if multiple files have the same name
            let uniqueFolder = tempDirectory.appendingPathComponent(UUID().uuidString)
            let destURL = uniqueFolder.appendingPathComponent(intentFile.fileURL?.lastPathComponent ?? intentFile.filename)
            do {
                try FileManager.default.createDirectory(at: uniqueFolder, withIntermediateDirectories: true)
                if let originalURL = intentFile.fileURL {
                    let accessing = originalURL.startAccessingSecurityScopedResource()
                    defer { if accessing { originalURL.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.copyItem(at: originalURL, to: destURL)
                } else {
                    // shortcuts can hand over files that only exist as data
                    try intentFile.data.write(to: destURL)
                }
                jobs.append((intentFile, destURL))
            } catch {
                print("INTENT: CAN'T PREPARE \(intentFile.filename): \(error)")
                jobs.append((intentFile, nil))
            }
        }
        let workingUrls = jobs.compactMap(\.workingCopy)

        // 5. execute processing
        let stream = await chisel.process(files: workingUrls)
        for await event in stream {
            switch event {
            // a container's own recompression is followed by its final rebuild, which reports the result
            case .finish(let path, let before, let after, _, _, let isContainer) where !isContainer && after < before:
                let url = URL(fileURLWithPath: path)

                // only track the root requested files, ignoring internal extracted files
                if workingUrls.contains(where: { $0.path == url.path }) {
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

        // every input comes out, in order: chisel only replaces a working copy it made smaller, so files it
        // skipped, couldn't improve or failed on come out unchanged, and the shortcut can go on with all of them
        let outputFiles = jobs.map { job in
            job.workingCopy.map { IntentFile(fileURL: $0) } ?? job.input
        }
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

import AppIntents
import ChiselKit
import SwiftData
import Foundation

struct CompressFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Compress with Chisel"
    static var description = IntentDescription("Compresses the provided files using the Chisel engine.")

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
        let maxTokens = UInt32(defaults.integer(forKey: "maxTokens") == 0 ? 10000 : defaults.integer(forKey: "maxTokens"))
        let threads = UInt32(defaults.integer(forKey: "threads") == 0 ? 4 : defaults.integer(forKey: "threads"))

        // 2. setup isolated swiftdata context
        let container = try ModelContainer(for: CompressionStat.self)
        let context = ModelContext(container)

        // 3. setup chisel engine
        let chisel = Chisel()
        await chisel.configure(
            iterations: iterations,
            iterationsLarge: iterationsLarge,
            maxTokens: maxTokens,
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
            let destURL = tempDirectory.appendingPathComponent(originalURL.lastPathComponent)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            try? FileManager.default.copyItem(at: originalURL, to: destURL)
            workingUrls.append(destURL)
        }

        // 5. execute processing
        let stream = await chisel.process(files: workingUrls)
        var outputFiles: [IntentFile] = []

        for await event in stream {
            switch event {
            case .finish(let path, let before, let after, _):
                let url = URL(fileURLWithPath: path)

                // only export and track the root requested files, ignoring internal extracted files
                if workingUrls.contains(where: { $0.lastPathComponent == url.lastPathComponent }) {
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

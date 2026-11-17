import AppIntents
import ChiselKit
import SwiftData
import Foundation

/// An App Intent that exposes Chisel's compression capabilities to Apple Shortcuts and Siri.
/// This allows users to compress files directly from the Finder context menu or automated workflows.
struct CompressFilesIntent: AppIntent, ProgressReportingIntent {
    static let title: LocalizedStringResource = "Compress with Chisel"
    static let description = IntentDescription("Compresses the provided files using the Chisel engine.")

    /// The list of files provided by the user or the shortcut input.
    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.item"])
    var files: [IntentFile]

    /// Where the compressed files go.
    @Parameter(title: "Save Mode", default: .appSetting)
    var saveMode: CompressionSaveMode

    /// Destination when saving in a folder.
    @Parameter(title: "Folder", supportedTypeIdentifiers: ["public.folder"])
    var folder: IntentFile?

    static var parameterSummary: some ParameterSummary {
        When(\.$saveMode, .equalTo, .folder) {
            Summary("Compress \(\.$files) and save them in \(\.$folder)")
        } otherwise: {
            Summary("Compress \(\.$files) and \(\.$saveMode)")
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let startTime = Date()
        // the system shows this progress with the app's icon wherever the shortcut runs
        progress.localizedDescription = String(localized: "Compressing with Chisel…")
        progress.localizedAdditionalDescription = String(localized: "Analyzing files…")

        // 1. read preferences matching @appstorage keys
        let defaults = UserDefaults.standard

        // where compressed files go: nil keeps them as copies, handed back to the shortcut
        let outputMode: OutputMode?
        var destinationFolder: URL?
        switch saveMode {
        case .returnCopy:
            outputMode = nil
        case .overwrite:
            outputMode = .overwrite
        case .sideBySide:
            outputMode = .sideBySide
        case .keepOriginal:
            outputMode = .keepOriginal
        case .folder:
            guard let folderURL = folder?.fileURL else { throw $folder.needsValueError() }
            outputMode = .outputFolder
            destinationFolder = folderURL
        case .appSetting:
            let appMode = defaults.string(forKey: "outputMode").flatMap(OutputMode.init(rawValue:)) ?? .keepOriginal
            outputMode = appMode
            if appMode == .outputFolder {
                destinationFolder = defaults.data(forKey: "outputFolderBookmark").flatMap(OutputMode.resolveOutputFolder)?.url
                guard destinationFolder != nil else { throw CompressFilesIntentError.noOutputFolder }
            }
        }
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
        // every file chisel analyzes, the ones found inside containers too, counts once it reaches its final result;
        // the total is only known once the analysis ends, since it keeps finding files inside containers until then
        var analyzed: Set<String> = []
        var settled: Set<String> = []
        var analysisFinished = false
        var improved: Set<String> = []

        func reportProgress() {
            progress.localizedAdditionalDescription = String(localized: "\(analyzed.count - settled.count) files left")
            progress.totalUnitCount = Int64(analyzed.count)
            progress.completedUnitCount = Int64(settled.count)
        }

        func settle(_ path: String) {
            guard analyzed.contains(path), settled.insert(path).inserted, analysisFinished else { return }
            reportProgress()
        }

        let stream = await chisel.process(files: workingUrls)
        for await event in stream {
            switch event {
            case .analyzeComplete(let path, _, _, _):
                analyzed.insert(path)
            case .start, .finalizeStart:
                if !analysisFinished {
                    analysisFinished = true
                    reportProgress()
                }
            // a container's own recompression is followed by its final rebuild, which reports the result
            case .finish(let path, let before, let after, _, _, let isContainer) where !isContainer:
                settle(path)
                let url = URL(fileURLWithPath: path)

                // only track the root requested files, ignoring internal extracted files
                if after < before, workingUrls.contains(where: { $0.path == url.path }) {
                    improved.insert(url.path)
                    let duration = Date().timeIntervalSince(startTime)
                    let stat = CompressionStat(
                        fileExtension: url.pathExtension,
                        originalSize: Int64(before),
                        compressedSize: Int64(after),
                        durationSeconds: duration
                    )
                    context.insert(stat)
                }
            case .skipped(let path, _, _, let isContainer, _) where !isContainer:
                settle(path)
            case .error(let path, _, _, let isContainer) where !isContainer:
                settle(path)
            default:
                break
            }
        }
        progress.completedUnitCount = progress.totalUnitCount

        try context.save()

        // every input comes out, in order, so the shortcut can go on with all of them: files chisel skipped,
        // couldn't improve or failed on as they came, the others where the save mode put them
        var outputFiles: [IntentFile] = []
        var failures: [String] = []
        for job in jobs {
            guard let workingCopy = job.workingCopy, improved.contains(workingCopy.path) else {
                outputFiles.append(job.input)
                continue
            }
            // files that only came as data have no original to save next to
            guard let outputMode, let original = job.input.fileURL else {
                outputFiles.append(IntentFile(fileURL: workingCopy))
                continue
            }
            do {
                let saved = try outputMode.place(workingCopy, for: original, outputFolder: destinationFolder)
                outputFiles.append(IntentFile(fileURL: saved))
            } catch {
                failures.append("\(original.lastPathComponent): \(error.localizedDescription)")
                outputFiles.append(IntentFile(fileURL: workingCopy))
            }
        }
        if !failures.isEmpty {
            throw CompressFilesIntentError.saveFailed(failures.joined(separator: "\n"))
        }
        return .result(value: outputFiles)
    }
}

/// Where the Compress with Chisel action puts the compressed files.
enum CompressionSaveMode: String, AppEnum {
    case appSetting
    case returnCopy
    case overwrite
    case sideBySide
    case keepOriginal
    case folder

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Save Mode"

    // read after "Compress <files> and ..." in the action's summary
    static let caseDisplayRepresentations: [CompressionSaveMode: DisplayRepresentation] = [
        .appSetting: "save them as set in Chisel",
        .returnCopy: "only return the compressed copies",
        .overwrite: "overwrite the originals",
        .sideBySide: "save them next to the originals",
        .keepOriginal: "rename the originals and take their place",
        .folder: "save them in a folder"
    ]
}

enum CompressFilesIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noOutputFolder
    case saveFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noOutputFolder:
            return "Chisel's save mode is set to a custom folder, but no folder is selected in its settings."
        case .saveFailed(let details):
            return "Chisel compressed the files but couldn't save some of them:\n\(details)"
        }
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

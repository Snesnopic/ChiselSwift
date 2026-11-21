import Foundation
import Observation
import UniformTypeIdentifiers
import ChiselKit
import SwiftData
import SwiftUI

/// The primary view model responsible for managing the file queue and orchestrating the `ChiselKit` compression engine.
@Observable
@MainActor
final class ChiselViewModel {
    init(input: [FileItem] = []) {
        items = input
    }

    /// The current list of files queued for processing.
    var items: [FileItem] = []

    /// Files that are known to be unsupported and were explicitly skipped during import.
    var unsupportedURLs: [URL] = []

    /// Application-wide processing logs, spanning all files.
    var logs: [String] = []

    /// Indicates whether the compression engine is currently active.
    var isProcessing = false

    /// Indicates whether a graceful shutdown of the engine has been requested.
    var isStopping = false

    /// Indicates whether files are currently being copied and imported into the queue.
    var isImporting: Bool { importTaskCount > 0 }
    private var importTaskCount: Int = 0

    /// Returns true if there is at least one pending file ready for processing.
    var canStartProcessing: Bool {
        !isProcessing && !isImporting && !items.isEmpty && items.contains { $0.status == .pending }
    }

    private var currentChisel: Chisel?

    var libraryVersion: String = "Loading..."
    var supportedExtensions: [String] = []
    func fetchVersion() {
        Task {
            let chisel = Chisel()
            let version = await chisel.version
            let extensions = await chisel.supportedExtensions
            self.libraryVersion = version
            self.supportedExtensions = extensions
        }
    }

    var activeSecurityBookmarks: Set<URL> = []
    @ObservationIgnored
    @AppStorage("outputFolderBookmark") private var outputFolderBookmark: Data?
    @ObservationIgnored
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @ObservationIgnored
    @AppStorage("verifyChecksums") private var verifyChecksums: Bool = false
    @ObservationIgnored
    @AppStorage("breakSignatures") private var breakSignatures: Bool = false
    var sessionAuthorizedFolders: Set<URL> = []

    func saveBookmark(for url: URL) {
            do {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }

                #if os(macOS)
                let options: URL.BookmarkCreationOptions = .withSecurityScope
                #else
                let options: URL.BookmarkCreationOptions = .minimalBookmark
                #endif

                let bookmarkData = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
                self.outputFolderBookmark = bookmarkData
            } catch {
                print("ERROR SAVING BOOKMARK: \(error)")
            }
        }
    func getOutputFolderURL() -> URL? {
        guard let data = outputFolderBookmark, let resolved = OutputMode.resolveOutputFolder(from: data) else { return nil }
        if resolved.isStale {
            saveBookmark(for: resolved.url)
        }
        return resolved.url
    }

    func findMissingPermissionDirectory(for mode: OutputMode) -> URL? {
            if mode == .overwrite { return nil }

            if mode == .outputFolder && getOutputFolderURL() == nil {
                return URL(fileURLWithPath: "GLOBAL_OUTPUT_FOLDER")
            }

            if mode == .sideBySide || mode == .keepOriginal {
                for item in items where item.status == .pending {
                    let dir = item.url.deletingLastPathComponent()
                    if !FileManager.default.isWritableFile(atPath: dir.path) && !sessionAuthorizedFolders.contains(dir) {
                        return dir
                    }
                }
            }
            return nil
        }

    func addFiles(urls: [URL], recursive: Bool) {
        print("IMPORTING \(urls.count) ROOT ITEMS (RECURSIVE: \(recursive))")
        let tempDirectory = FileManager.default.temporaryDirectory
        importTaskCount += 1

        Task {
            defer { importTaskCount -= 1 }
            for rootURL in urls {
                // start accessing the root folder/file provided by the system
                guard rootURL.startAccessingSecurityScopedResource() else {
                    print("FAILED TO ACCESS SECURITY SCOPED RESOURCE: \(rootURL.lastPathComponent)")
                    continue
                }
                activeSecurityBookmarks.insert(rootURL)

                var filesToProcess: [URL] = []
                var isDir: ObjCBool = false

                if FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue {
                    // it's a directory, extract children
                    filesToProcess = expandDirectory(at: rootURL, recursive: recursive)
                } else {
                    // it's a single file
                    filesToProcess.append(rootURL)
                }
                let chisel = Chisel()
                // copy children while the parent's security scope is still active
                for fileURL in filesToProcess {
                    let bool = await chisel.isCompatible(file: fileURL)
                    guard bool else {
                        if !unsupportedURLs.contains(fileURL) {
                            unsupportedURLs.append(fileURL)
                            print("SKIPPED UNSUPPORTED FILE: \(fileURL.lastPathComponent)")
                        }
                        continue
                    }
                    guard !items.contains(where: { $0.url == fileURL && $0.status == .pending }) else {
                        print("ALREADY QUEUED: \(fileURL.lastPathComponent)")
                        continue
                    }

                    // own folder per copy: files with the same name (e.g. from different subfolders) must not share one
                    let destinationURL = tempDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                        .appendingPathComponent(fileURL.lastPathComponent)

                do {
                    try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: fileURL, to: destinationURL)

                    let attr = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                    let size = attr[.size] as? Int64 ?? 0

                    let item = FileItem(
                        url: fileURL,
                        tempURL: destinationURL,
                        status: .pending,
                        size: size,
                        originalExtension: destinationURL.pathExtension.lowercased()
                    )

                    items.append(item)
                    print("ADDED FILE: \(destinationURL.lastPathComponent)")
                } catch {
                    print("ERROR PREPARING FILE: \(error)")
                }
            }
        }
        }

    }

    private func expandDirectory(at url: URL, recursive: Bool) -> [URL] {
        var files: [URL] = []
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

        if recursive {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options) {
                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                       let isDirectory = resourceValues.isDirectory, !isDirectory {
                        files.append(fileURL)
                    }
                }
            }
        } else {
            if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options) {
                for fileURL in contents {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                       let isDirectory = resourceValues.isDirectory, !isDirectory {
                        files.append(fileURL)
                    }
                }
            }
        }
        return files
    }

    // swiftlint:disable cyclomatic_complexity function_parameter_count
    // coordinates the chiselkit engine
    func startProcessing(iterations: Int, iterationsLarge: Int, threads: Int, hideUnsupported: Bool, outputMode: OutputMode, dryRun: Bool = false, context: ModelContext) async {
        guard !items.isEmpty else { return }

        // filter to process only pending items
        let pendingItems = items.filter { $0.status == .pending }
        guard !pendingItems.isEmpty else { return }

        let urlsToProcess = pendingItems.map { $0.tempURL }
        isProcessing = true
        print("STARTING BATCH PROCESSING WITH \(iterations) ITERATIONS, \(threads) THREADS")

        let chisel = Chisel()
        currentChisel = chisel

        await chisel.configure(
            iterations: UInt32(iterations),
            iterationsLarge: UInt32(iterationsLarge),
            preserveMetadata: preserveMetadata,
            verifyChecksums: verifyChecksums,
            breakSignatures: breakSignatures,
            dryRun: dryRun,
            threads: UInt32(threads)
        )

        var pendingStats: [CompressionStat] = []
        var startTimes: [String: CFAbsoluteTime] = [:]
#if os(macOS)
        MenuBarProgressManager.shared.show()
#endif

        // every event names the container its file came from, and a container is announced
        // before anything inside it, so the tree can be built as events arrive
        for await event in await chisel.process(files: urlsToProcess) {
            switch event {

            case .analyzeStart(let path):
                // nested containers get their node once their analysis completes
                guard exactIndexPath(for: path, in: items) != nil else { break }
                updateItem(for: path, createIfNeeded: false) { parent, child, isRoot in
                    let msg = "ANALYZING CONTAINER"
                    if isRoot {
                        parent.status = .processing
                        parent.logs.append(msg)
                        logs.append("\(msg): \(parent.url.lastPathComponent)")
                    } else {
                        child?.status = .processing
                        child?.logs.append("[CHILD] \(msg)")
                    }
                }

            case .analyzeComplete(let path, let extracted, let numChildren, let parentContainer):
                guard extracted else { break }
                registerContainer(path: path, numChildren: numChildren, parentContainer: parentContainer)

            case .start(let path, let parentContainer, _):
                startTimes[path] = CFAbsoluteTimeGetCurrent()

                // .start is ONLY emitted for real compression targets, so we safely create the UI node
                updateItem(for: path, createIfNeeded: true, parentHint: parentContainer) { parent, child, isRoot in
                    if isRoot {
                        parent.status = .processing
                        parent.logs.append("STARTED PROCESSING")
                        logs.append("STARTED PROCESSING: \(parent.url.lastPathComponent)")
                    } else {
                        child?.status = .processing
                        child?.logs.append("STARTED EXTRACTED FILE")

                        if parent.status != .processing {
                            parent.status = .processing
                        }

                        let msg = "[CHILD] STARTED: \(URL(fileURLWithPath: path).lastPathComponent)"
                        parent.logs.append(msg)
                        logs.append(msg)
                    }
                }

            case .finish(let path, let sizeBefore, let sizeAfter, _, let parentContainer, let isContainerSelf):
                updateItem(for: path, createIfNeeded: true, parentHint: parentContainer) { parent, child, isRoot in
                    let targetName = URL(fileURLWithPath: path).lastPathComponent
                    let isGain = sizeBefore > sizeAfter

                    // For "mixed" processors (Flac/Ape), this event is only the container's own
                    // direct recompression pass, not its final state: chisel still has to finalize
                    // (Phase 3) the same original path to re-embed extracted content (e.g. cover art).
                    // Finalizing/moving the temp file now would race with that later step and crash
                    // the engine when it can't find the file it expects anymore. Just log progress
                    // and wait for the matching finalize event (isContainer == false) to finalize.
                    if isContainerSelf {
                        let msg = isGain
                            ? "COMPRESSED CONTAINER STREAM: \(targetName) (finalizing embedded content...)"
                            : "NO GAIN ON CONTAINER STREAM: \(targetName) (finalizing embedded content...)"
                        if isRoot {
                            parent.logs.append(msg)
                        } else {
                            child?.logs.append(msg)
                        }
                        logs.append(msg)
                        return
                    }

                    var finalMsg = isGain ? "SUCCESSFULLY COMPRESSED: \(targetName) (saved \(formatBytes(Int64(sizeBefore - sizeAfter))))" : "NO GAIN: \(targetName)"

                    var finalizationFailed = false

                    if isGain && !dryRun {
                        do {
                            let itemToFinalize = isRoot ? parent : (child ?? parent)
                            try self.finalizeFile(item: itemToFinalize, mode: outputMode)
                        } catch {
                            finalizationFailed = true
                            finalMsg = "ERROR SAVING \(targetName): \(error.localizedDescription)"
                        }
                    } else if isGain && dryRun {
                        finalMsg = "SIMULATED COMPRESSION: \(targetName) (would save \(formatBytes(Int64(sizeBefore - sizeAfter))))"
                    }

                    if isRoot {
                        parent.sizeAfter = Int64(sizeAfter)
                        parent.status = finalizationFailed ? .error("Save failed") : (isGain ? (dryRun ? .simulated : .completed(parent.url)) : .noGain)
                        parent.logs.append(finalMsg)
                        logs.append(finalMsg)
                        Self.settleContents(of: &parent)

                        if isGain && !finalizationFailed && !dryRun {
                            let duration = CFAbsoluteTimeGetCurrent() - (startTimes[path] ?? CFAbsoluteTimeGetCurrent())
                            let stat = CompressionStat(
                                fileExtension: parent.originalExtension,
                                originalSize: Int64(sizeBefore),
                                compressedSize: Int64(sizeAfter),
                                durationSeconds: duration
                            )
                            pendingStats.append(stat)
                        }
                    } else {
                        if let unwrappedChild = child {
                            var localChild = unwrappedChild
                            localChild.size = Int64(sizeBefore)
                            localChild.sizeAfter = Int64(sizeAfter)
                            localChild.status = finalizationFailed ? .error("Save failed") : (isGain ? (dryRun ? .simulated : .completed(localChild.url)) : .noGain)
                            localChild.logs.append(finalMsg)
                            Self.settleContents(of: &localChild)
                            child = localChild
                        }
                        parent.logs.append("[CHILD] \(finalMsg)")
                        logs.append("[CHILD] \(finalMsg)")
                    }
                }
            case .error(let path, let message, let parentContainer, let isContainerSelf):
                updateItem(for: path, createIfNeeded: true, parentHint: parentContainer) { parent, child, isRoot in
                    let targetName = URL(fileURLWithPath: path).lastPathComponent
                    let errorMsg = "ERROR [\(targetName)]: \(message)"

                    // a failed recompression of a container's own stream isn't final: its rebuild still runs
                    if isRoot {
                        parent.status = .error(message)
                        parent.logs.append(errorMsg)
                        logs.append(errorMsg)
                        if !isContainerSelf { Self.settleContents(of: &parent) }
                    } else {
                        if var failed = child {
                            failed.status = .error(message)
                            failed.logs.append(errorMsg)
                            if !isContainerSelf { Self.settleContents(of: &failed) }
                            child = failed
                        }
                        parent.logs.append("[CHILD] \(errorMsg)")
                        logs.append("[CHILD] \(errorMsg)")
                    }
                }

            case .skipped(let path, let reason, let message, let parentContainer, let isContainerSelf):
                // files that are supported but were left alone stay visible; the rest is what "hide unsupported" hides
                let shouldHideChild: Bool
                let computedStatus: FileItem.ProcessingStatus
                switch reason {
                case .noImprovement:
                    shouldHideChild = false
                    computedStatus = .noGain
                case .interrupted:
                    shouldHideChild = false
                    computedStatus = .stopped
                case .signed, .readOnly, .changedDuringRun:
                    shouldHideChild = false
                    computedStatus = .skipped
                case .junk, .empty, .unsupported, .nestingTooDeep, .nothingToDo:
                    shouldHideChild = hideUnsupported
                    computedStatus = .skipped
                }
                let skipNote: String? = switch reason {
                case .readOnly:
                    String(localized: "Read-only", comment: "File inspector value: the file was skipped because it can't be written.")
                case .changedDuringRun:
                    String(localized: "Changed during the run", comment: "File inspector value: the file was skipped because something else changed it while Chisel was working on it.")
                default:
                    nil
                }

                updateItem(for: path, createIfNeeded: !shouldHideChild, parentHint: parentContainer) { parent, child, isRoot in
                    let targetName = URL(fileURLWithPath: path).lastPathComponent
                    let skipMsg = reason == .interrupted ? "INTERRUPTED [\(targetName)]" : "SKIPPED [\(targetName)]: \(message)"

                    // a container's own stream being skipped isn't final: its rebuild still decides
                    if isRoot {
                        parent.status = computedStatus
                        parent.skipNote = skipNote
                        parent.logs.append(skipMsg)
                        logs.append(skipMsg)
                        if !isContainerSelf { Self.settleContents(of: &parent) }
                    } else {
                        if shouldHideChild {
                            child = nil // Enforce removal just in case it existed
                            // we DO NOT append logs for hidden files to save main thread performance
                        } else {
                            if var skipped = child {
                                skipped.status = computedStatus
                                skipped.skipNote = skipNote
                                skipped.logs.append(skipMsg)
                                if !isContainerSelf { Self.settleContents(of: &skipped) }
                                child = skipped
                            }
                            parent.logs.append("[CHILD] \(skipMsg)")
                            logs.append("[CHILD] \(skipMsg)")
                        }
                    }
                }

            case .finalizeStart(let path):
                updateItem(for: path, createIfNeeded: false) { parent, child, isRoot in
                    let msg = "RE-ASSEMBLING CONTAINER..."
                    if isRoot {
                        parent.logs.append(msg)
                        logs.append("\(parent.url.lastPathComponent) - \(msg)")
                    } else {
                        child?.logs.append("[CHILD] \(msg)")
                    }
                }

            case .log(let tag, let message, let level):
                print("CHISELKIT LOG: [\(level)] [\(tag)] \(message)")

                // chisel's internal Debug-level tracing (e.g. "Entering/Exiting recompress
                // for X") fires per-file and would flood the UI; keep it console-only.
                if level != "DEBUG" {
                    logs.append("[\(level)] [\(tag)] \(message)")
                }
            }
        }

        // stream has finished. check if it was due to a user stop.
        if isStopping {
            markRemainingAsStopped()
            isStopping = false
        }

        for stat in pendingStats {
            context.insert(stat)
        }
        try? context.save()

        isProcessing = false
        currentChisel = nil
        print("BATCH PROCESSING COMPLETED")
#if os(macOS)
        MenuBarProgressManager.shared.hide()
#endif
    }
    // swiftlint:enable cyclomatic_complexity function_parameter_count

    func stopProcessing() {
        guard isProcessing, !isStopping else { return }

        isStopping = true
        print("USER REQUESTED STOP, WAITING FOR THREADS TO JOIN...")

        Task {
            await currentChisel?.stop()
            // we DO NOT set isProcessing = false here. startProcessing will handle it.
        }
    }

    // recursively updates files that were interrupted
    private func markRemainingAsStopped() {
        var localItems = items
        var logsToAppend: [String] = []

        // files still waiting for analysis when the stop arrived get no event; the rest do, and containers settle their contents
        func traverseAndMark(nodes: inout [FileItem]) {
            for i in 0..<nodes.count {
                let currentStatus = nodes[i].status

                if case .pending = currentStatus {
                    nodes[i].status = .stopped
                    nodes[i].logs.append("PROCESS ABORTED BY USER")
                    logsToAppend.append("[\(nodes[i].url.lastPathComponent)] PROCESS ABORTED BY USER")
                } else if case .processing = currentStatus {
                    nodes[i].status = .stopped
                    nodes[i].logs.append("PROCESS INTERRUPTED BY USER")
                    logsToAppend.append("[\(nodes[i].url.lastPathComponent)] PROCESS INTERRUPTED BY USER")
                }

                if nodes[i].children != nil {
                    traverseAndMark(nodes: &nodes[i].children!)
                }
            }
        }

        // mutate local copy
        traverseAndMark(nodes: &localItems)

        // write back exactly once
        items = localItems

        // safely trigger observable side-effects
        if !logsToAppend.isEmpty {
            logs.append(contentsOf: logsToAppend)
        }
    }

    func clearItems() {
        for url in activeSecurityBookmarks {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityBookmarks.removeAll()

        items.removeAll()
        logs.removeAll()
        print("CLEARED ALL ITEMS AND LOGS")
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func removeItems(at offsets: IndexSet) {
        let indicesToRemove = offsets.filter { index in
            let item = items[index]
            let isProcessing = item.status == .processing || (item.children?.contains { $0.status == .processing } ?? false)

            if isProcessing {
                print("PREVENTED DELETION OF PROCESSING FILE: \(item.url.lastPathComponent)")
            }
            return !isProcessing
        }
        items.remove(atOffsets: IndexSet(indicesToRemove))
    }

    private func registerContainer(path: String, numChildren: Int, parentContainer: String?) {
        updateItem(for: path, createIfNeeded: true, parentHint: parentContainer) { parent, child, isRoot in
            let msg = "EXTRACTION COMPLETE: FOUND \(numChildren) FILES"
            if isRoot {
                parent.logs.append(msg)
                logs.append("\(parent.url.lastPathComponent) - \(msg)")
            } else {
                child?.status = .processing
                child?.logs.append("[CHILD] \(msg)")
            }
        }
    }

    // what a container's final result means for its contents, whose results only reach disk inside it:
    // all of them fail with it, on no gain or if it was left as it was (e.g. changed during the run) the ones
    // that had shrunk are discarded, and if a stop kept it from being rebuilt nothing they achieved is kept
    private static func settleContents(of container: inout FileItem) {
        guard container.children != nil else { return }
        let name = container.url.lastPathComponent
        switch container.status {
        case .error:
            markContents(&container.children!) { status in
                if case .error = status { return nil }
                return (.error("Container \(name) failed"), "ERROR: CONTAINER \(name) FAILED, NOTHING INSIDE IT WAS SAVED")
            }
        case .noGain:
            markContents(&container.children!) { status in
                switch status {
                case .completed, .simulated:
                    return (.skipped, "DISCARDED: CONTAINER \(name) DID NOT GET SMALLER")
                default:
                    return nil
                }
            }
        case .skipped:
            markContents(&container.children!) { status in
                switch status {
                case .completed, .simulated:
                    return (.skipped, "DISCARDED: CONTAINER \(name) WAS LEFT AS IT WAS")
                default:
                    return nil
                }
            }
        case .stopped:
            markContents(&container.children!) { status in
                switch status {
                case .completed, .noGain, .simulated:
                    return (.stopped, "DISCARDED: CONTAINER \(name) WAS NOT REBUILT")
                default:
                    return nil
                }
            }
        default:
            break
        }
    }

    private static func markContents(_ nodes: inout [FileItem], _ rule: (FileItem.ProcessingStatus) -> (FileItem.ProcessingStatus, String)?) {
        for idx in nodes.indices {
            if let (status, log) = rule(nodes[idx].status) {
                nodes[idx].status = status
                nodes[idx].sizeAfter = nil
                nodes[idx].logs.append(log)
            }
            if nodes[idx].children != nil {
                markContents(&nodes[idx].children!, rule)
            }
        }
    }

    private func exactIndexPath(for path: String, in nodes: [FileItem]) -> [Int]? {
        for idx in nodes.indices {
            if nodes[idx].tempURL.path == path {
                return [idx]
            }
            if let children = nodes[idx].children, let childPath = exactIndexPath(for: path, in: children) {
                return [idx] + childPath
            }
        }
        return nil
    }

    private func findIndexPath(for path: String, parentHint: String? = nil, in nodes: [FileItem]) -> [Int]? {
        if let exact = exactIndexPath(for: path, in: nodes) {
            return exact
        }
        // a file that has no node yet goes under the container chisel says it came from
        if let parentHint {
            return exactIndexPath(for: parentHint, in: nodes)
        }
        return nil
    }

    private func updateItem(for path: String, createIfNeeded: Bool = true, parentHint: String? = nil, action: (inout FileItem, inout FileItem?, Bool) -> Void) {
        guard let indexPath = findIndexPath(for: path, parentHint: parentHint, in: items), !indexPath.isEmpty else { return }

        func applyAction(nodes: inout [FileItem], indices: ArraySlice<Int>) {
            let idx = indices.first!

            if indices.count == 1 {
                if nodes[idx].tempURL.path == path {
                    // EXACT MATCH AT ROOT LEVEL
                    var dummyChild: FileItem?
                    action(&nodes[idx], &dummyChild, true)
                } else {
                    // PARENT MATCH, TARGET IS A CHILD
                    let existingChildIdx = nodes[idx].children?.firstIndex(where: { $0.tempURL.path == path })

                    if let cIdx = existingChildIdx {
                        var targetChild: FileItem? = nodes[idx].children![cIdx]
                        action(&nodes[idx], &targetChild, false)
                        if let valid = targetChild {
                            nodes[idx].children![cIdx] = valid
                        } else {
                            nodes[idx].children!.remove(at: cIdx)
                        }
                    } else if createIfNeeded {
                        if nodes[idx].children == nil { nodes[idx].children = [] }
                        let childURL = URL(fileURLWithPath: path)
                        var newChild: FileItem? = FileItem(
                            url: childURL,          // for extracted files, original and temp are the same
                            tempURL: childURL,      // they only exist in the temp directory
                            status: .pending,
                            size: 0,
                            originalExtension: childURL.pathExtension.lowercased()
                        )
                        action(&nodes[idx], &newChild, false)
                        if let valid = newChild {
                            nodes[idx].children!.append(valid)
                        }
                    } else {
                        // Child doesn't exist and won't be created, but we still trigger the closure for the parent log
                        var dummyChild: FileItem?
                        action(&nodes[idx], &dummyChild, false)
                    }
                }
            } else {
                // INTERCEPT NESTED MATCH
                if indices.count == 2 {
                    let childIdx = indices.dropFirst().first!
                    if nodes[idx].children![childIdx].tempURL.path == path {
                        var targetChild: FileItem? = nodes[idx].children![childIdx]
                        action(&nodes[idx], &targetChild, false)
                        if let valid = targetChild {
                            nodes[idx].children![childIdx] = valid
                        } else {
                            nodes[idx].children!.remove(at: childIdx)
                        }
                        return
                    }
                }

                // TRAVERSE DEEPER
                if nodes[idx].children != nil {
                    applyAction(nodes: &nodes[idx].children!, indices: indices.dropFirst())
                }
            }
        }

                let rootIndex = indexPath.first!
                let rootItem = items[rootIndex]
                var localNodes = [rootItem]

                var relativeIndices = Array(indexPath)
                relativeIndices[0] = 0

                applyAction(nodes: &localNodes, indices: ArraySlice(relativeIndices))

                items[rootIndex] = localNodes[0]
                updateMenuBarProgress()
    }

    private func updateMenuBarProgress() {
#if os(macOS)
        let snapshot = self.items
        let completed = snapshot.filter {
            switch $0.status {
            case .completed, .noGain, .error, .skipped: return true
            default: return false
            }
        }.count
        let total = snapshot.count
        let percentage = total > 0 ? Double(completed) / Double(total) : 0
        MenuBarProgressManager.shared.updateProgress(percentage)
#endif
    }

    private func finalizeFile(item: FileItem, mode: OutputMode) throws {
        // ignore items that are only temporary (extracted children)
        // the parent container will handle the finalization
        guard item.url.path != item.tempURL.path else { return }
        _ = try mode.place(item.tempURL, for: item.url, outputFolder: mode == .outputFolder ? getOutputFolderURL() : nil)
    }
    func findItem(with id: UUID, in searchItems: [FileItem]? = nil) -> FileItem? {
        let source = searchItems ?? items
        for item in source {
            if item.id == id { return item }
            if let children = item.children, let found = findItem(with: id, in: children) {
                return found
            }
        }
        return nil
    }
}

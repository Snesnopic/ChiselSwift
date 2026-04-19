import Foundation
import Observation
import UniformTypeIdentifiers
import ChiselKit
import SwiftData
import SwiftUI

@Observable
@MainActor
final class ChiselViewModel {
    var items: [FileItem] = []
    var logs: [String] = []
    var isProcessing = false
    var isStopping = false
    // check if there are files ready for compression
    var canStartProcessing: Bool {
        !isProcessing && !items.isEmpty && items.contains { $0.status == .pending }
    }

    var activeSecurityBookmarks: Set<URL> = []
#if os(macOS)
    @ObservationIgnored
    @AppStorage("outputFolderBookmark") private var outputFolderBookmark: Data?

    func selectOutputFolder() {

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
        }

    }

    private func saveBookmark(for url: URL) {
        do {
            // create a persistent bookmark
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            self.outputFolderBookmark = bookmarkData
        } catch {
            print("ERROR SAVING BOOKMARK: \(error)")
        }
    }

    func getOutputFolderURL() -> URL? {
        guard let data = outputFolderBookmark else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // bookmark is old, should ask again or refresh
                saveBookmark(for: url)
            }
            return url
        } catch {
            print("ERROR RESOLVING BOOKMARK: \(error)")
            return nil
        }
    }
#endif

    func addFiles(urls: [URL], recursive: Bool) {
        print("IMPORTING \(urls.count) ROOT ITEMS (RECURSIVE: \(recursive))")
        let tempDirectory = FileManager.default.temporaryDirectory

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

            // copy children while the parent's security scope is still active
            for fileURL in filesToProcess {
                let destinationURL = tempDirectory.appendingPathComponent(fileURL.lastPathComponent)

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }

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

                    if !items.contains(where: { $0.url == destinationURL }) {
                        items.append(item)
                        print("ADDED FILE: \(destinationURL.lastPathComponent)")
                    }
                } catch {
                    print("ERROR PREPARING FILE: \(error)")
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

    // coordinates the chiselkit engine
    func startProcessing(iterations: Int, iterationsLarge: Int, maxTokens: Int, threads: Int, hideUnsupported: Bool, outputMode: OutputMode, context: ModelContext) async {
        guard !items.isEmpty else { return }

        // filter to process only pending items
        let pendingItems = items.filter { $0.status == .pending }
        guard !pendingItems.isEmpty else { return }

        let urlsToProcess = pendingItems.map { $0.tempURL }
        isProcessing = true
        print("STARTING BATCH PROCESSING WITH \(iterations) ITERATIONS, \(maxTokens) TOKENS, \(threads) THREADS")

        let chisel = Chisel()

        await chisel.configure(
            iterations: UInt32(iterations),
            iterationsLarge: UInt32(iterationsLarge),
            maxTokens: UInt32(maxTokens),
            threads: UInt32(threads)
        )

        var pendingStats: [CompressionStat] = []
        var startTimes: [String: CFAbsoluteTime] = [:]
#if os(macOS)
        await MenuBarProgressManager.shared.show(isDeterminate: true)
#endif

        for await event in await chisel.process(files: urlsToProcess) {
            switch event {

            case .analyzeStart(let path):
                // creates the child UI node ONLY if it's a known container format, preventing .bin flickering
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                let isContainer = ["zip", "pdf", "rar", "7z", "tar", "gz"].contains(ext)

                updateItem(for: path, createIfNeeded: isContainer) { parent, child, isRoot in
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

            case .analyzeComplete(let path, let extracted, let numChildren):
                // if it extracted files, it's definitively a container. Create it if missed.
                updateItem(for: path, createIfNeeded: extracted) { parent, child, isRoot in
                    let msg = "EXTRACTION COMPLETE: FOUND \(numChildren) FILES"
                    if extracted {
                        if isRoot {
                            parent.logs.append(msg)
                            logs.append("\(parent.url.lastPathComponent) - \(msg)")
                        } else {
                            child?.logs.append("[CHILD] \(msg)")
                        }
                    }
                }

            case .start(let path):
                startTimes[path] = CFAbsoluteTimeGetCurrent()

                // .start is ONLY emitted for real compression targets, so we safely create the UI node
                updateItem(for: path, createIfNeeded: true) { parent, child, isRoot in
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

            case .finish(let path, let sizeBefore, let sizeAfter, _):
                updateItem(for: path, createIfNeeded: true) { parent, child, isRoot in
                    let targetName = URL(fileURLWithPath: path).lastPathComponent
                    let isGain = sizeBefore > sizeAfter
                    var finalMsg = isGain ? "SUCCESSFULLY COMPRESSED: \(targetName) (saved \(formatBytes(Int64(sizeBefore - sizeAfter))))" : "NO GAIN: \(targetName)"

                    var finalizationFailed = false

                    if isGain {
                        do {
                            let itemToFinalize = isRoot ? parent : (child ?? parent)
                            try self.finalizeFile(item: itemToFinalize, mode: outputMode)
                        } catch {
                            finalizationFailed = true
                            finalMsg = "ERROR SAVING \(targetName): \(error.localizedDescription)"
                        }
                    }

                    if isRoot {
                        parent.sizeAfter = Int64(sizeAfter)
                        parent.status = finalizationFailed ? .error("Save failed") : (isGain ? .completed(parent.url) : .noGain)
                        parent.logs.append(finalMsg)
                        logs.append(finalMsg)

                        if isGain && !finalizationFailed {
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
                            localChild.status = finalizationFailed ? .error("Save failed") : (isGain ? .completed(localChild.url) : .noGain)
                            localChild.logs.append(finalMsg)
                            child = localChild
                        }
                        parent.logs.append("[CHILD] \(finalMsg)")
                        logs.append("[CHILD] \(finalMsg)")
                    }
#if os(macOS)
                    // calculate overall percentage based on a snapshot to avoid exclusivity violations
                    let snapshot = self.items
                    let completed = snapshot.filter { if case .completed = $0.status { return true }; return false }.count
                    let total = snapshot.count
                    let percentage = total > 0 ? Double(completed) / Double(total) : 0
                    MenuBarProgressManager.shared.updateProgress(percentage)

#endif
                }

            case .error(let path, let message):
                updateItem(for: path, createIfNeeded: true) { parent, child, isRoot in
                    let targetName = URL(fileURLWithPath: path).lastPathComponent
                    let errorMsg = "ERROR [\(targetName)]: \(message)"

                    if isRoot {
                        parent.status = .error(message)
                        parent.logs.append(errorMsg)
                        logs.append(errorMsg)
                    } else {
                        child?.status = .error(message)
                        child?.logs.append(errorMsg)
                        parent.logs.append("[CHILD] \(errorMsg)")
                        logs.append("[CHILD] \(errorMsg)")
                    }
                }

            case .skipped(let path, let reason):
                let lowerReason = reason.lowercased()
                let isNoGain = lowerReason.contains("no gain") || lowerReason.contains("size")
                let shouldHideChild = hideUnsupported && !isNoGain

                // create child UI node only if it's a "no gain" skip. Otherwise, discard it entirely.
                updateItem(for: path, createIfNeeded: !shouldHideChild) { parent, child, isRoot in
                    let targetName = URL(fileURLWithPath: path).lastPathComponent
                    let skipMsg = "SKIPPED [\(targetName)]: \(reason)"
                    let computedStatus: FileItem.ProcessingStatus = isNoGain ? .noGain : .skipped

                    if isRoot {
                        parent.status = computedStatus
                        parent.logs.append(skipMsg)
                        logs.append(skipMsg)
                    } else {
                        if shouldHideChild {
                            child = nil // Enforce removal just in case it existed
                            // we DO NOT append logs for hidden files to save main thread performance
                        } else {
                            child?.status = computedStatus
                            child?.logs.append(skipMsg)
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

            case .log(let tag, let message):
                logs.append("[\(tag)] \(message)")
                print("CHISELKIT LOG: [\(tag)] \(message)")
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
        print("BATCH PROCESSING COMPLETED")
    }

    func stopProcessing() {
        guard isProcessing, !isStopping else { return }

        isStopping = true
        print("USER REQUESTED STOP, WAITING FOR THREADS TO JOIN...")

        let chisel = Chisel()
        Task {
            await chisel.stop()
            // we DO NOT set isProcessing = false here. startProcessing will handle it.
        }
    }

    // recursively updates files that were interrupted
    private func markRemainingAsStopped() {
        var localItems = items
        var logsToAppend: [String] = []

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

    private func findIndexPath(for path: String, in nodes: [FileItem]) -> [Int]? {
        if let idx = nodes.firstIndex(where: { $0.tempURL.path == path }) {
            return [idx]
        }

        for idx in 0..<nodes.count {
            if let children = nodes[idx].children, let childPath = findIndexPath(for: path, in: children) {
                return [idx] + childPath
            }
        }

        let pathURL = URL(fileURLWithPath: path)
        let folderName = pathURL.deletingLastPathComponent().lastPathComponent

        for idx in 0..<nodes.count {
            let parentURL = nodes[idx].url
            let baseName = parentURL.deletingPathExtension().lastPathComponent

            if !baseName.isEmpty {
                let isArchiveFolder = folderName.hasPrefix("archive_\(baseName)_")
                let isExtractionFolder = folderName.hasPrefix("\(baseName)-")
                let isExactFolder = folderName == baseName

                if isArchiveFolder || isExtractionFolder || isExactFolder {
                    return [idx]
                }
            }
        }

        return nil
    }

    private func updateItem(for path: String, createIfNeeded: Bool = true, action: (inout FileItem, inout FileItem?, Bool) -> Void) {
        guard let indexPath = findIndexPath(for: path, in: items), !indexPath.isEmpty else { return }

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
                var rootItem = items[rootIndex]
                var localNodes = [rootItem]

                var relativeIndices = Array(indexPath)
                relativeIndices[0] = 0

                applyAction(nodes: &localNodes, indices: ArraySlice(relativeIndices))

                items[rootIndex] = localNodes[0]
    }

    private func generateUniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { return url }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let name = url.deletingPathExtension().lastPathComponent

        var counter = 1
        var newURL = url

        while fm.fileExists(atPath: newURL.path) {
            newURL = dir.appendingPathComponent("\(name)-\(counter)").appendingPathExtension(ext)
            counter += 1
        }

        return newURL
    }

    private func finalizeFile(item: FileItem, mode: OutputMode) throws {
        let fm = FileManager.default
        let original = item.url
        let temp = item.tempURL

        // ignore items that are only temporary (extracted children)
        // the parent container will handle the finalization
        guard original.path != temp.path else { return }

        let originalNoExt = original.deletingPathExtension()
        let ext = original.pathExtension

        // start access to the original resource (held by the bookmark/active access)
        guard original.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "ChiselError", code: 1, userInfo: [NSLocalizedDescriptionKey: "PERMISSION DENIED FOR ORIGINAL FILE"])
        }
        defer { original.stopAccessingSecurityScopedResource() }

        switch mode {
        case .overwrite:
            print("OVERWRITING ORIGINAL: \(original.lastPathComponent)")
            _ = try fm.replaceItemAt(original, withItemAt: temp)

        case .sideBySide:
            var newURL = originalNoExt.appendingPathExtension("compressed").appendingPathExtension(ext)
            newURL = generateUniqueURL(for: newURL)
            print("SAVING SIDE-BY-SIDE: \(newURL.lastPathComponent)")
            try fm.moveItem(at: temp, to: newURL)

        case .keepOriginal:
            var backupURL = originalNoExt.appendingPathExtension("original").appendingPathExtension(ext)
            backupURL = generateUniqueURL(for: backupURL)
            print("CREATING BACKUP AND SWAPPING: \(backupURL.lastPathComponent)")
            try fm.moveItem(at: original, to: backupURL)
            try fm.moveItem(at: temp, to: original)
#if os(macOS)
        case .outputFolder:
            if let destFolder = getOutputFolderURL() {
                if destFolder.startAccessingSecurityScopedResource() {
                    var destURL = destFolder.appendingPathComponent(original.lastPathComponent)
                    destURL = generateUniqueURL(for: destURL)
                    print("MOVING TO CUSTOM FOLDER: \(destURL.path)")
                    try? fm.removeItem(at: destURL)
                    try fm.moveItem(at: temp, to: destURL)
                    destFolder.stopAccessingSecurityScopedResource()
                }
            }
#endif
        }
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

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

    func addFiles(urls: [URL], recursive: Bool) {
        print("IMPORTING \(urls.count) ROOT ITEMS (RECURSIVE: \(recursive))")
        let tempDirectory = FileManager.default.temporaryDirectory

        for rootURL in urls {
            // start accessing the root folder/file provided by the system
            guard rootURL.startAccessingSecurityScopedResource() else {
                print("FAILED TO ACCESS SECURITY SCOPED RESOURCE: \(rootURL.lastPathComponent)")
                continue
            }

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
                        url: destinationURL,
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

            // release the root security scope only after all copies are done
            rootURL.stopAccessingSecurityScopedResource()
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
    func startProcessing(iterations: Int, iterationsLarge: Int, maxTokens: Int, threads: Int, hideUnsupported: Bool, context: ModelContext) async {
        guard !items.isEmpty else { return }

        // filter to process only pending items
        let pendingItems = items.filter { $0.status == .pending }
        guard !pendingItems.isEmpty else { return }

        let urlsToProcess = pendingItems.map { $0.url }
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
                    let finalMsg = isGain ? "SUCCESSFULLY COMPRESSED: \(targetName) (saved \(formatBytes(Int64(sizeBefore - sizeAfter))))" : "NO GAIN: \(targetName)"

                    if isRoot {
                        parent.sizeAfter = Int64(sizeAfter)
                        parent.status = isGain ? .completed(parent.url) : .noGain
                        parent.logs.append(finalMsg)
                        logs.append(finalMsg)

                        if isGain {
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
                            localChild.status = isGain ? .completed(localChild.url) : .noGain
                            localChild.logs.append(finalMsg)
                            child = localChild
                        }
                        parent.logs.append("[CHILD] \(finalMsg)")
                        logs.append("[CHILD] \(finalMsg)")
                    }
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
            markRemainingAsStopped(nodes: &items)
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
    private func markRemainingAsStopped(nodes: inout [FileItem]) {
        for i in 0..<nodes.count {
            let currentStatus = nodes[i].status

            // if the file hasn't finished, mark it as stopped
            // adjust this if your enum differs (e.g., matching .pending or .processing)
            if case .pending = currentStatus {
                nodes[i].status = .stopped
                nodes[i].logs.append("PROCESS ABORTED BY USER")
                logs.append("[\(nodes[i].url.lastPathComponent)] PROCESS ABORTED BY USER")
            } else if case .processing = currentStatus {
                nodes[i].status = .stopped
                nodes[i].logs.append("PROCESS INTERRUPTED BY USER")
                logs.append("[\(nodes[i].url.lastPathComponent)] PROCESS INTERRUPTED BY USER")
            }

            if nodes[i].children != nil {
                markRemainingAsStopped(nodes: &nodes[i].children!)
            }
        }
    }

    func clearItems() {
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
        if let idx = nodes.firstIndex(where: { $0.url.path == path }) {
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

    // updated signature: explicit createIfNeeded flag and isRoot boolean inside the closure
    private func updateItem(for path: String, createIfNeeded: Bool = true, action: (inout FileItem, inout FileItem?, Bool) -> Void) {
        guard let indexPath = findIndexPath(for: path, in: items), !indexPath.isEmpty else { return }

        func applyAction(nodes: inout [FileItem], indices: ArraySlice<Int>) {
            let idx = indices.first!

            if indices.count == 1 {
                if nodes[idx].url.path == path {
                    // EXACT MATCH AT ROOT LEVEL
                    var dummyChild: FileItem?
                    action(&nodes[idx], &dummyChild, true)
                } else {
                    // PARENT MATCH, TARGET IS A CHILD
                    let existingChildIdx = nodes[idx].children?.firstIndex(where: { $0.url.path == path })

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
                            url: childURL,
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
                    if nodes[idx].children![childIdx].url.path == path {
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

        applyAction(nodes: &items, indices: ArraySlice(indexPath))
    }
}

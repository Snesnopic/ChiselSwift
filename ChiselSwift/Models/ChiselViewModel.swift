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
    
    // check if there are files ready for compression
    var canStartProcessing: Bool {
        !isProcessing && !items.isEmpty && items.contains { $0.status == .pending }
    }
    
    // handles security scoped file import
    func addFiles(urls: [URL]) {
        print("IMPORTING \(urls.count) FILES")
        let tempDirectory = FileManager.default.temporaryDirectory
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                print("FAILED TO ACCESS SECURITY SCOPED RESOURCE: \(url.lastPathComponent)")
                continue
            }
            
            let destinationURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
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
            
            url.stopAccessingSecurityScopedResource()
        }
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
        
        // map to track individual execution times
        var startTimes: [String: CFAbsoluteTime] = [:]
        
        for await event in await chisel.process(files: urlsToProcess) {
            print("RAW EVENT FROM CHISEL: \(event)")
            switch event {
                
            case .analyzeStart(let path):
                updateItem(for: path) { parent, child, _ in
                    let msg = "ANALYZING CONTAINER"
                    if child != nil {
                        child?.status = .processing
                        child?.logs.append("[CHILD] \(msg)")
                    } else {
                        parent.status = .processing
                        parent.logs.append(msg)
                        logs.append("\(msg): \(parent.url.lastPathComponent)")
                    }
                }
                
            case .analyzeComplete(let path, let extracted, let numChildren):
                if extracted {
                    updateItem(for: path) { parent, child, _ in
                        let msg = "EXTRACTION COMPLETE: FOUND \(numChildren) FILES"
                        if child != nil {
                            child?.logs.append("[CHILD] \(msg)")
                        } else {
                            parent.logs.append(msg)
                            logs.append("\(parent.url.lastPathComponent) - \(msg)")
                        }
                    }
                }
                
            case .start(let path):
                startTimes[path] = CFAbsoluteTimeGetCurrent()
                updateItem(for: path) { parent, child, _ in
                    if child != nil {
                        child?.status = .processing
                        child?.logs.append("STARTED EXTRACTED FILE")
                        parent.status = .processing
                        
                        // propagate to parent and global
                        let msg = "[CHILD] STARTED: \(child!.url.lastPathComponent)"
                        parent.logs.append(msg)
                        logs.append(msg)
                    } else {
                        parent.status = .processing
                        parent.logs.append("STARTED PROCESSING")
                        logs.append("STARTED PROCESSING: \(parent.url.lastPathComponent)")
                    }
                }
                
            case .finish(let path, let sizeBefore, let sizeAfter, let replaced):
                updateItem(for: path) { parent, child, index in
                    let targetName = child != nil ? child!.url.lastPathComponent : parent.url.lastPathComponent
                    let successMsg = "SUCCESSFULLY COMPRESSED: \(targetName) (saved \(formatBytes(Int64(sizeBefore - sizeAfter))))"
                    let noGainMsg = "NO GAIN: \(targetName)"
                    
                    if let unwrappedChild = child {
                        var localChild = unwrappedChild
                        localChild.size = Int64(sizeBefore)
                        localChild.sizeAfter = Int64(sizeAfter)
                        if sizeBefore > sizeAfter {
                            localChild.status = .completed(localChild.url)
                            localChild.logs.append(successMsg)
                            parent.logs.append("[CHILD] \(successMsg)")
                            logs.append("[CHILD] \(successMsg)")
                        } else {
                            localChild.status = .noGain
                            localChild.logs.append(noGainMsg)
                            parent.logs.append("[CHILD] \(noGainMsg)")
                            logs.append("[CHILD] \(noGainMsg)")
                        }
                        child = localChild
                    } else {
                        // update parent (final event for this tree)
                        parent.sizeAfter = Int64(sizeAfter)
                        if sizeBefore > sizeAfter {
                            parent.status = .completed(parent.url)
                            parent.logs.append(successMsg)
                            logs.append(successMsg) // global log
                            
                            // save stats only for parent
                            let duration = CFAbsoluteTimeGetCurrent() - (startTimes[path] ?? CFAbsoluteTimeGetCurrent())
                            let stat = CompressionStat(
                                fileExtension: parent.originalExtension,
                                originalSize: Int64(sizeBefore),
                                compressedSize: Int64(sizeAfter),
                                durationSeconds: duration
                            )
                            pendingStats.append(stat)
                        } else {
                            parent.status = .noGain
                            parent.logs.append(noGainMsg)
                            logs.append(noGainMsg)
                        }
                    }
                }
                
            case .error(let path, let message):
                updateItem(for: path) { parent, child, _ in
                    let targetName = child != nil ? child!.url.lastPathComponent : parent.url.lastPathComponent
                    let errorMsg = "ERROR [\(targetName)]: \(message)"
                    
                    if child != nil {
                        child?.status = .error(message)
                        child?.logs.append(errorMsg)
                        parent.logs.append("[CHILD] \(errorMsg)")
                        logs.append("[CHILD] \(errorMsg)")
                    } else {
                        parent.status = .error(message)
                        parent.logs.append(errorMsg)
                        logs.append(errorMsg)
                    }
                }
                
            case .skipped(let path, let reason):
                updateItem(for: path) { parent, child, _ in
                    let targetName = child != nil ? child!.url.lastPathComponent : parent.url.lastPathComponent
                    let skipMsg = "SKIPPED [\(targetName)]: \(reason)"
                    let lowerReason = reason.lowercased()
                    let computedStatus: FileItem.ProcessingStatus = (lowerReason.contains("no gain") || lowerReason.contains("size")) ? .noGain : .skipped
                    
                    if child != nil {
                        parent.status = .processing
                        // discard unsupported child files if flag is active
                        if hideUnsupported && lowerReason.contains("unsupported format") {
                            child = nil
                        } else {
                            child?.status = computedStatus
                            child?.logs.append(skipMsg)
                            parent.logs.append("[CHILD] \(skipMsg)")
                            logs.append("[CHILD] \(skipMsg)")
                        }
                    } else {
                        parent.status = computedStatus
                        parent.logs.append(skipMsg)
                        logs.append(skipMsg)
                    }
                }
                
            case .finalizeStart(let path):
                updateItem(for: path) { parent, child, _ in
                    let msg = "RE-ASSEMBLING CONTAINER..."
                    if child != nil {
                        child?.logs.append("[CHILD] \(msg)")
                    } else {
                        parent.logs.append(msg)
                        logs.append("\(parent.url.lastPathComponent) - \(msg)")
                    }
                }
                
            case .log(let tag, let message):
                // global logs that cannot be mapped to a specific path
                logs.append("[\(tag)] \(message)")
                print("CHISELKIT LOG: [\(tag)] \(message)")
            }
        }
        
        for stat in pendingStats {
            context.insert(stat)
        }
        try? context.save()
        
        isProcessing = false
        print("BATCH PROCESSING COMPLETED")
    }
    
    // halt engine execution
    func stopProcessing() {
        let chisel = Chisel()
        Task {
            await chisel.stop()
            isProcessing = false
            print("PROCESSING STOPPED BY USER")
        }
    }
    
    // reset state
    func clearItems() {
        items.removeAll()
        logs.removeAll()
        print("CLEARED ALL ITEMS AND LOGS")
    }
    
    // utilities
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    func removeItems(at offsets: IndexSet) {
        let indicesToRemove = offsets.filter { index in
            let item = items[index]
            // check if item or any of its children are currently processing
            let isProcessing = item.status == .processing || (item.children?.contains { $0.status == .processing } ?? false)
            
            if isProcessing {
                print("PREVENTED DELETION OF PROCESSING FILE: \(item.url.lastPathComponent)")
            }
            
            return !isProcessing
        }
        
        items.remove(atOffsets: IndexSet(indicesToRemove))
    }
    
    // recursively find the exact index path to the deepest matching parent
    private func findIndexPath(for path: String, in nodes: [FileItem]) -> [Int]? {
        // exact match
        if let idx = nodes.firstIndex(where: { $0.url.path == path }) {
            return [idx]
        }
        
        // post-order traversal to find the deepest valid parent first
        for idx in 0..<nodes.count {
            if let children = nodes[idx].children, let childPath = findIndexPath(for: path, in: children) {
                return [idx] + childPath
            }
        }
        
        let pathURL = URL(fileURLWithPath: path)
        let folderName = pathURL.deletingLastPathComponent().lastPathComponent
        
        // check if current node is the parent using strict folder boundary matching
        for idx in 0..<nodes.count {
            let parentURL = nodes[idx].url
            let baseName = parentURL.deletingPathExtension().lastPathComponent
            
            if !baseName.isEmpty {
                // strict matching against chisel c++ temporary directory formats
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

    
    // route event to parent or child based on path using n-level recursion
    private func updateItem(for path: String, action: (inout FileItem, inout FileItem?, Int) -> Void) {
        guard let indexPath = findIndexPath(for: path, in: items), !indexPath.isEmpty else { return }
        
        func applyAction(nodes: inout [FileItem], indices: ArraySlice<Int>) {
            let idx = indices.first!
            
            if indices.count == 1 {
                if nodes[idx].url.path == path {
                    // exact match at root level
                    var dummyParent = nodes[idx]
                    var targetChild: FileItem? = nodes[idx]
                    
                    action(&dummyParent, &targetChild, idx)
                    
                    if let valid = targetChild {
                        nodes[idx] = valid
                    } else {
                        nodes.remove(at: idx)
                    }
                } else {
                    // parent match, append child
                    if nodes[idx].children == nil {
                        nodes[idx].children = []
                    }
                    
                    let childURL = URL(fileURLWithPath: path)
                    var newChild: FileItem? = FileItem(
                        url: childURL,
                        status: .pending,
                        size: 0,
                        originalExtension: childURL.pathExtension.lowercased()
                    )
                    
                    action(&nodes[idx], &newChild, nodes[idx].children?.count ?? 0)
                    
                    if let valid = newChild {
                        nodes[idx].children!.append(valid)
                    }
                }
            } else {
                // intercept exact match of a nested child to provide the real parent
                if indices.count == 2 {
                    let childIdx = indices.dropFirst().first!
                    if nodes[idx].children![childIdx].url.path == path {
                        var targetChild: FileItem? = nodes[idx].children![childIdx]
                        
                        action(&nodes[idx], &targetChild, childIdx)
                        
                        if let valid = targetChild {
                            nodes[idx].children![childIdx] = valid
                        } else {
                            nodes[idx].children!.remove(at: childIdx)
                        }
                        return
                    }
                }
                
                // traverse deeper into the tree
                if nodes[idx].children != nil {
                    applyAction(nodes: &nodes[idx].children!, indices: indices.dropFirst())
                }
            }
        }
        
        applyAction(nodes: &items, indices: ArraySlice(indexPath))
    }

    // helper function to extract child by path
    private func getChild(at path: [Int], from node: FileItem) -> FileItem {
        var current = node
        for index in path {
            current = current.children![index]
        }
        return current
    }
    
    // helper function to mutate nested structs
    private func setChild(_ child: FileItem, at path: [Int], in node: inout FileItem) {
        if path.count == 1 {
            node.children?[path[0]] = child
        } else {
            var nextNode = node.children![path[0]]
            setChild(child, at: Array(path.dropFirst()), in: &nextNode)
            node.children?[path[0]] = nextNode
        }
    }
    
    // helper function to delete nested structs
    private func removeChild(at path: [Int], in node: inout FileItem) {
        if path.count == 1 {
            node.children?.remove(at: path[0])
        } else {
            var nextNode = node.children![path[0]]
            removeChild(at: Array(path.dropFirst()), in: &nextNode)
            node.children?[path[0]] = nextNode
        }
    }
    
    
}

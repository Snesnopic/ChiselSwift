import Foundation
import Observation
import UniformTypeIdentifiers
import ChiselKit
import SwiftData

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
    func startProcessing(iterations: Int, iterationsLarge: Int, maxTokens: Int, threads: Int, context: ModelContext) async {
        guard !items.isEmpty else { return }
        // filter to process only pending items
        let pendingItems = items.filter { $0.status == .pending }
        guard !pendingItems.isEmpty else { return }
        
        isProcessing = true
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
            case .start(let path):
                startTimes[path] = CFAbsoluteTimeGetCurrent()
                if let index = items.firstIndex(where: { $0.url.path == path }) {
                    items[index].status = .processing
                    items[index].logs.append("STARTED PROCESSING")
                }
                
            case .finish(let path, let sizeBefore, let sizeAfter, let replaced):
                if let index = items.firstIndex(where: { $0.url.path == path }) {
                    items[index].sizeAfter = Int64(sizeAfter)
                    let filename = items[index].url.lastPathComponent
                    
                    if sizeBefore > sizeAfter {
                        items[index].status = .completed(items[index].url)
                        
                        let duration = CFAbsoluteTimeGetCurrent() - (startTimes[path] ?? CFAbsoluteTimeGetCurrent())
                        let stat = CompressionStat(
                            fileExtension: items[index].originalExtension,
                            originalSize: Int64(sizeBefore),
                            compressedSize: Int64(sizeAfter),
                            durationSeconds: duration
                        )
                        pendingStats.append(stat)
                        
                        let saved = formatBytes(Int64(sizeBefore - sizeAfter))
                        let successMsg = "SUCCESSFULLY COMPRESSED: \(filename) (saved \(saved))"
                        
                        items[index].logs.append(successMsg)
                        logs.append(successMsg)
                        print("FINISHED PROCESSING: \(filename), replaced: \(replaced)")
                    } else {
                        items[index].status = .noGain
                        let noGainMsg = "NO GAIN: \(filename)"
                        
                        items[index].logs.append(noGainMsg)
                        logs.append(noGainMsg)
                        print("NO GAIN FOR: \(filename)")
                    }
                }
                
            case .error(let path, let message):
                if let index = items.firstIndex(where: { $0.url.path == path }) {
                    items[index].status = .error(message)
                    let filename = items[index].url.lastPathComponent
                    let errorMsg = "ERROR [\(filename)]: \(message)"
                    
                    items[index].logs.append(errorMsg)
                    logs.append(errorMsg)
                    print("ERROR PROCESSING \(filename): \(message)")
                }
                
            case .skipped(let path, let reason):
                if let index = items.firstIndex(where: { $0.url.path == path }) {
                    let lowerReason = reason.lowercased()
                    if lowerReason.contains("no gain") || lowerReason.contains("size") {
                        items[index].status = .noGain
                    } else {
                        items[index].status = .skipped
                    }
                    
                    let skipMsg = "SKIPPED [\(items[index].url.lastPathComponent)]: \(reason)"
                    items[index].logs.append(skipMsg)
                    logs.append(skipMsg)
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
}

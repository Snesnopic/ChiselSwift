import SwiftUI
import UniformTypeIdentifiers
import ChiselKit

struct ContentView: View {
    @State private var items: [FileItem] = []
    @State private var logs: [String] = []
    @State private var isProcessing = false
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var sortOption: SortOption = .name
    
    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @AppStorage("verifyChecksums") private var verifyChecksums: Bool = false
    @AppStorage("threads") private var threads: Int = 4
    
    private let chisel = Chisel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sort by", selection: $sortOption) {
                    Text("Name").tag(SortOption.name)
                    Text("Size").tag(SortOption.size)
                    Text("Category").tag(SortOption.category)
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: sortOption) { _ in sortItems() }
                
                List(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.originalUrl.lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                        
                        HStack {
                            Text(item.category.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(formatBytes(item.originalSize))
                                .foregroundColor(.secondary)
                                .font(.system(.caption, design: .monospaced))
                            
                            if item.status == .processing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .padding(.leading, 4)
                            } else if item.status == .done, let newSize = item.newSize {
                                let saved = item.originalSize > newSize ? item.originalSize - newSize : 0
                                let percentage = item.originalSize > 0 ? (Double(saved) / Double(item.originalSize)) * 100 : 0
                                
                                Text("\(formatBytes(newSize)) (-\(String(format: "%.1f", percentage))%)")
                                    .foregroundColor(.green)
                                    .font(.system(.caption, design: .monospaced))
                            } else if item.status == .error {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                Divider()
                
                VStack(spacing: 16) {
                    HStack {
                        Button(action: { showPicker = true }) {
                            Label("Add files", systemImage: "plus.circle")
                        }
                        .disabled(isProcessing)
                        
                        Spacer()
                        
                        Button(action: clearItems) {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(isProcessing || items.isEmpty)
                        .foregroundColor(.red)
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: startProcessing) {
                            Text("Start")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isProcessing || items.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button(action: { Task { await chisel.stop() } }) {
                            Text("Stop")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(!isProcessing)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
            }
            .navigationTitle("Chisel")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showLogs = true }) {
                        Image(systemName: "terminal")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showLogs) {
                NavigationStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading) {
                                ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .id(index)
                                }
                            }
                            .padding()
                        }
                        .background(Color(uiColor: .systemGroupedBackground))
                        .onChange(of: logs.count, perform: { _ in
                            if !logs.isEmpty { proxy.scrollTo(logs.count - 1, anchor: .bottom) }
                        })
                    }
                    .navigationTitle("Logs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") { showLogs = false }
                        }
                    }
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): addFiles(urls)
                case .failure(let error):
                    logs.append(String(localized:"Picker error: \(error.localizedDescription)"))
                    showLogs = true
                }
            }
        }
    }
    
    // securely copy files to temp dir and extract metadata
    private func addFiles(_ urls: [URL]) {
        Task {
            for originalUrl in urls {
                guard !items.contains(where: { $0.originalUrl == originalUrl }) else { continue }
                
                // 1. request secure access to the icloud file
                let hasAccess = originalUrl.startAccessingSecurityScopedResource()
                
                // 2. copy to a safe local sandbox path
                let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + originalUrl.lastPathComponent)
                
                do {
                    try FileManager.default.copyItem(at: originalUrl, to: tempUrl)
                    
                    // 3. read size and mime from the local copy (no permission issues)
                    let size = (try? tempUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let mime = await chisel.getMimeType(for: tempUrl)
                    let category = mimeToCategory(mime)
                    
                    let item = FileItem(
                        originalUrl: originalUrl,
                        workingUrl: tempUrl,
                        category: category,
                        originalSize: UInt64(size)
                    )
                    items.append(item)
                    
                } catch {
                    logs.append(String(localized:"Failed to read \(originalUrl.lastPathComponent): \(error.localizedDescription)"))
                }
                
                if hasAccess {
                    originalUrl.stopAccessingSecurityScopedResource()
                }
            }
            sortItems()
        }
    }
    
    private func sortItems() {
        items.sort { a, b in
            switch sortOption {
            case .name: return a.originalUrl.lastPathComponent < b.originalUrl.lastPathComponent
            case .size: return a.originalSize > b.originalSize
            case .category: return a.category.displayName < b.category.displayName
            }
        }
    }
    
    private func updateItemByWorkingPath(_ path: String, updater: (inout FileItem) -> Void) {
        if let index = items.firstIndex(where: { $0.workingUrl.path == path }) {
            updater(&items[index])
        }
    }
    
    private func clearItems() {
        // cleanup temp files
        for item in items {
            try? FileManager.default.removeItem(at: item.workingUrl)
        }
        items.removeAll()
        logs.removeAll()
    }
    
    private func startProcessing() {
        isProcessing = true
        let pendingItems = items.filter { $0.status != .done }
        let workingUrls = pendingItems.map { $0.workingUrl }
        
        if workingUrls.isEmpty {
            isProcessing = false
            return
        }
        
        Task {
                    await chisel.configure(
                        iterations: UInt32(iterations),
                        iterationsLarge: UInt32(iterationsLarge),
                        maxTokens: UInt32(maxTokens),
                        preserveMetadata: preserveMetadata,
                        verifyChecksums: verifyChecksums,
                        threads: UInt32(threads),
                        outputDirectory: nil
                    )
                    
            logs.append(String(localized:"Starting process with \(threads) threads..."))
                    let stream = await chisel.process(files: workingUrls)
                    
                    for await event in stream {
                        switch event {
                        case .start(let path):
                            let eventUrl = URL(fileURLWithPath: path)
                            let isTopLevel = items.contains(where: { $0.workingUrl.path == path })
                            
                            if isTopLevel {
                                updateItemByWorkingPath(path) { $0.status = .processing }
                                logs.append(String(localized:"-> Processing container: \(eventUrl.lastPathComponent)"))
                            } else {
                                // it's an extracted internal file (e.g. image inside pdf)
                                logs.append(String(localized:"   -> Processing internal: \(eventUrl.lastPathComponent)"))
                            }
                            
                        case .finish(let path, let before, let after, let replaced):
                            let eventUrl = URL(fileURLWithPath: path)
                            
                            // check if it's the top-level container that finished
                            if let index = items.firstIndex(where: { $0.workingUrl.path == path }) {
                                let item = items[index]
                                
                                if replaced || after < before {
                                    let hasAccess = item.originalUrl.startAccessingSecurityScopedResource()
                                    do {
                                        let optimizedData = try Data(contentsOf: URL(fileURLWithPath: path))
                                        try optimizedData.write(to: item.originalUrl, options: .atomic)
                                    } catch {
                                        logs.append(String(localized:"Error saving: \(error.localizedDescription)"))
                                    }
                                    if hasAccess { item.originalUrl.stopAccessingSecurityScopedResource() }
                                }
                                
                                items[index].status = .done
                                items[index].originalSize = before
                                items[index].newSize = after
                                
                                let saved = before > after ? before - after : 0
                                logs.append(String(describing:"Ok: \(item.originalUrl.lastPathComponent) (saved \(formatBytes(saved)), replaced: \(replaced))"))
                            } else {
                                // internal file finished
                                let saved = before > after ? before - after : 0
                                logs.append(String(localized:"   Ok internal: \(eventUrl.lastPathComponent) (saved \(formatBytes(saved)))"))
                            }
                            
                        case .error(let path, let msg):
                            if let index = items.firstIndex(where: { $0.workingUrl.path == path }) {
                                items[index].status = .error
                                items[index].errorMessage = msg
                            }
                            let name = URL(fileURLWithPath: path).lastPathComponent
                            logs.append(String(localized:"Error on \(name): \(msg)"))
                            
                        case .log(let tag, let msg):
                            logs.append("[\(tag)] \(msg)")
                        }
                    }
                    logs.append(String(localized:"Completed."))
                    isProcessing = false
                }
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}


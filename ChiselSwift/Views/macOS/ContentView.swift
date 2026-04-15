import SwiftUI
import UniformTypeIdentifiers
import ChiselKit

struct ContentView: View {
    @State private var items: [FileItem] = []
    @State private var logs: [String] = []
    @State private var isProcessing = false
    @State private var showPicker = false
    @State private var showLogs = false
    @State private var sortOption: SortOption = .name
    
    @AppStorage("iterations") private var iterations: Int = 1
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 1
    @AppStorage("maxTokens") private var maxTokens: Int = 8192
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @AppStorage("verifyChecksums") private var verifyChecksums: Bool = true
    @AppStorage("threads") private var threads: Int = 4
    
    private let chisel = Chisel()
    
    var body: some View {
        HStack(spacing: 0) {
            // main content area
            VStack(spacing: 0) {
                // simple toolbar for sorting and filtering (placeholder for future expansion)
                HStack {
                    Picker("Sort by", selection: $sortOption) {
                        Text("Name").tag(SortOption.name)
                        Text("Size").tag(SortOption.size)
                        Text("Category").tag(SortOption.category)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .onChange(of: sortOption) {
                        sortItems()
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation { showLogs.toggle() }
                    }) {
                        Image(systemName: showLogs ? "sidebar.right" : "sidebar.right")
                            .foregroundColor(showLogs ? .accentColor : .primary)
                    }
                    .help("Toggle logs sidebar")
                }
                .padding()
                
                Divider()
                
                // file list
                List(items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.workingUrl.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                            Text(item.category.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // original size
                        Text(formatBytes(item.originalSize))
                            .foregroundColor(.secondary)
                            .font(.system(.callout, design: .monospaced))
                        
                        // processing results
                        if item.status == .processing {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 8)
                        } else if item.status == .done, let newSize = item.newSize {
                            let saved = item.originalSize > newSize ? item.originalSize - newSize : 0
                            let percentage = item.originalSize > 0 ? (Double(saved) / Double(item.originalSize)) * 100 : 0
                            
                            Text("\(formatBytes(newSize)) (-\(String(format: "%.1f", percentage))%)")
                                .foregroundColor(.green)
                                .font(.system(.callout, design: .monospaced))
                                .padding(.leading, 8)
                        } else if item.status == .error {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .help(item.errorMessage ?? "Unknown error")
                                .padding(.leading, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
                
                // control bar
                HStack {
                    Button("Add files...") {
                        showPicker = true
                    }
                    .disabled(isProcessing)
                    
                    Button("Clear") {
                        items.removeAll()
                        logs.removeAll()
                    }
                    .disabled(isProcessing || items.isEmpty)
                    
                    Spacer()
                    
                    Button("Start") {
                        startProcessing()
                    }
                    .disabled(isProcessing || items.isEmpty)
                    .buttonStyle(.borderedProminent)
                    
                    Button("Stop") {
                        Task { await chisel.stop() }
                    }
                    .disabled(!isProcessing)
                    .tint(.red)
                }
                .padding()
            }
            
            // right sidebar for logs
            if showLogs {
                Divider()
                
                VStack(spacing: 0) {
                    Text("Logs")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
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
                        .onChange(of: logs.count) {
                            if !logs.isEmpty {
                                proxy.scrollTo(logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(width: 300)
                .background(Color(NSColor.textBackgroundColor))
                .transition(.move(edge: .trailing))
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                addFiles(urls)
            case .failure(let error):
                logs.append(String(localized:"Picker error: \(error.localizedDescription)"))
                showLogs = true
            }
        }
    }
    
    // add files and extract initial metadata asynchronously
        private func addFiles(_ urls: [URL]) {
            Task {
                for url in urls {
                    guard !items.contains(where: { $0.originalUrl == url }) else { continue }
                    
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let mime = await chisel.getMimeType(for: url)
                    
                    let item = FileItem(
                        originalUrl: url,
                        workingUrl: url, // on macos, working url is identical to original
                        category: mimeToCategory(mime),
                        originalSize: UInt64(size)
                    )
                    items.append(item)
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
        
        private func updateItemStatus(path: String, updater: (inout FileItem) -> Void) {
            if let index = items.firstIndex(where: { $0.workingUrl.path == path }) {
                updater(&items[index])
            }
        }
    
    private func startProcessing() {
        isProcessing = true
        
        // only process items that haven't been completed yet
        let pendingUrls = items.filter { $0.status != .done }.map { $0.workingUrl }
        if pendingUrls.isEmpty {
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
            
            let stream = await chisel.process(files: pendingUrls)
            
            for await event in stream {
                switch event {
                case .start(let path):
                    updateItemStatus(path: path) { $0.status = .processing }
                    logs.append(String(localized:"-> Processing: \(path)"))
                    
                case .finish(let path, let before, let after, let replaced):
                    updateItemStatus(path: path) {
                        $0.status = .done
                        $0.originalSize = before
                        $0.newSize = after
                    }
                    let saved = before > after ? before - after : 0
                    logs.append(String(describing:"Ok: \(path) (saved \(formatBytes(saved)), replaced: \(replaced))"))
                    
                case .error(let path, let msg):
                    updateItemStatus(path: path) {
                        $0.status = .error
                        $0.errorMessage = msg
                    }
                    logs.append(String(localized:"Error on \(path): \(msg)"))
                    
                case .log(let tag, let msg):
                    logs.append("[\(tag)] \(msg)")
                }
            }
            
            logs.append(String(localized:"Completed."))
            isProcessing = false
        }
    }
    
    // utility to format bytes
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}


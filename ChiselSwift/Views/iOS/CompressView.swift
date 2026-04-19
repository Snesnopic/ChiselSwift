import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CompressView: View {
    @State private var viewModel = ChiselViewModel()
    @State private var isImporterPresented = false

    // state for global logs modal
    @State private var showGlobalLogs = false

    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("threads") private var threads: Int = 4
    @AppStorage("hideUnsupported") private var hideUnsupported: Bool = true
    @AppStorage("recursiveFolderImport") private var recursiveFolderImport: Bool = true
    @AppStorage("outputMode") private var outputMode: OutputMode = .overwrite

    @Environment(\.modelContext) private var modelContext

    private var descriptionText: Text {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Text("Drag and drop files here, or use the add button to start compressing.")
        } else {
            return Text("Use the add button to select files to compress.")
        }
    }

    var body: some View {
        NavigationStack {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No files selected",
                    systemImage: "tray.and.arrow.down.fill",
                    description: descriptionText
                )
                .dropDestination(for: URL.self) { items, _ in
                    viewModel.addFiles(urls: items, recursive: recursiveFolderImport)
                    return true
                }
                .navigationTitle("Chisel")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isImporterPresented.toggle() }) {
                            Image(systemName: "plus")
                        }
                        .disabled(viewModel.isProcessing)
                    }
                }
                .fileImporter(
                    isPresented: $isImporterPresented,
                    allowedContentTypes: [.data, .folder],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        viewModel.addFiles(urls: urls, recursive: recursiveFolderImport)
                    case .failure(let error):
                        print("FILE IMPORT FAILED: \(error)")
                    }
                }
            } else {
                List {
                    Section("Files") {
                        ForEach(viewModel.items) { item in
                            RecursiveFileNodeView(item: item, viewModel: viewModel)
                        }
                        .onDelete { indexSet in
                            viewModel.removeItems(at: indexSet)
                        }
                    }
                }
                .navigationTitle("Chisel")
                .toolbar {
                    // open global logs
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showGlobalLogs.toggle() }) {
                            Image(systemName: "terminal")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { viewModel.clearItems() }) {
                            Image(systemName: "trash")
                        }
                        .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isImporterPresented.toggle() }) {
                            Image(systemName: "plus")
                        }
                        .disabled(viewModel.isProcessing)
                    }
                }
                .dropDestination(for: URL.self) { items, _ in
                    viewModel.addFiles(urls: items, recursive: recursiveFolderImport)
                    return true
                }
                .fileImporter(
                    isPresented: $isImporterPresented,
                    allowedContentTypes: [.data, .folder],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        viewModel.addFiles(urls: urls, recursive: recursiveFolderImport)
                    case .failure(let error):
                        print("FILE IMPORT FAILED: \(error)")
                    }
                }
                // sheet definition for global logs
                .sheet(isPresented: $showGlobalLogs) {
                    NavigationStack {
                        FileInspectorView(file: nil, allLogs: viewModel.logs)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { showGlobalLogs = false }
                                }
                            }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(action: {
                        Task {
                            await viewModel.startProcessing(
                                iterations: iterations,
                                iterationsLarge: iterationsLarge,
                                maxTokens: maxTokens,
                                threads: threads,
                                hideUnsupported: hideUnsupported,
                                outputMode: outputMode,
                                context: modelContext
                            )
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isStopping {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Stopping threads...")
                            } else if viewModel.isProcessing {
                                Image(systemName: "stop.fill")
                                Text("Stop processing")
                            } else {
                                Image(systemName: "play.fill")
                                Text("Start processing")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            viewModel.isStopping ? Color.orange :
                                (viewModel.isProcessing ? Color.red :
                                    (!viewModel.canStartProcessing ? Color.gray : Color.accentColor)))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding()
                    }
                    .disabled(viewModel.isStopping || (!viewModel.canStartProcessing && !viewModel.isProcessing))
                }
            }
        }
    }
}

struct RecursiveFileNodeView: View {
    let item: FileItem
    let viewModel: ChiselViewModel

    var body: some View {
        if let children = item.children, !children.isEmpty {
            DisclosureGroup {
                ForEach(children) { child in
                    RecursiveFileNodeView(item: child, viewModel: viewModel)
                }
            } label: {
                FileRowView(item: item, logs: viewModel.logs)
            }
        } else {
            FileRowView(item: item, logs: viewModel.logs)
        }
    }
}

// standalone view to ensure proper diffing
struct FileRowView: View {
    let item: FileItem
    let logs: [String]

    // checks if current status is an error
    private var isError: Bool {
        if case .error = item.status { return true }
        return false
    }

    var body: some View {
        NavigationLink(destination: FileInspectorView(file: item, allLogs: logs)) {
            HStack {
                Image(systemName: item.typeIconName)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isError ? .red : .blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading) {
                    Text(item.url.lastPathComponent)
                        .font(.headline)
                        .foregroundStyle(isError ? .red : .primary)

                    if let children = item.children, !children.isEmpty {
                        Text("\(children.count) files inside")
                            .font(.caption2)
                            .foregroundStyle(isError ? .red.opacity(0.8) : .secondary)
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(isError ? .red.opacity(0.8) : .secondary)
                    }
                }

                Spacer()

                StatusBadgeView(status: item.status)
            }
        }
    }
}

#Preview("Light mode") {
    CompressView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    CompressView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

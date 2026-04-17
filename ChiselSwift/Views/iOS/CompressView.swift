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
                .dropDestination(for: URL.self) { items, location in
                    viewModel.addFiles(urls: items)
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
                    allowedContentTypes: [.data],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        viewModel.addFiles(urls: urls)
                    case .failure(let error):
                        print("file import failed: \(error)")
                    }
                }
            } else {
                List {
                    Section("Files") {
                        ForEach(viewModel.items) { item in
                            // render disclosure group if there are children
                            if let children = item.children, !children.isEmpty {
                                DisclosureGroup {
                                    ForEach(children) { child in
                                        fileRow(for: child)
                                    }
                                } label: {
                                    fileRow(for: item)
                                }
                            } else {
                                // standard row for files without children
                                fileRow(for: item)
                            }
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
                .dropDestination(for: URL.self) { items, location in
                    viewModel.addFiles(urls: items)
                    return true
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
                                context: modelContext
                            )
                        }
                    }) {
                        Text(viewModel.isProcessing ? "Processing..." : "Start processing")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(!viewModel.canStartProcessing ? Color.gray : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding()
                    }
                    .disabled(!viewModel.canStartProcessing)
                    
                }
            }
        }
    }
    
    // reusable viewbuilder for file rows
    @ViewBuilder
    private func fileRow(for item: FileItem) -> some View {
        NavigationLink(destination: FileInspectorView(file: item, allLogs: viewModel.logs)) {
            HStack {
                Image(systemName: item.typeIconName)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(item.url.lastPathComponent)
                        .font(.headline)
                    
                    if let children = item.children, children.count > 0 {
                        Text("\(children.count) files inside")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.formatBytes(item.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

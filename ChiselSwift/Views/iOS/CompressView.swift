import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CompressView: View {
    @State private var missingFolderURL: URL?
    @State private var showPermissionAlert = false
    @State private var isPermissionPickerPresented = false

    @State var viewModel = ChiselViewModel()
    @State private var isImporterPresented = false

    // state for global logs modal
    @State private var showGlobalLogs = false

    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("threads") private var threads: Int = 4
    @AppStorage("hideUnsupported") private var hideUnsupported: Bool = true
    @AppStorage("recursiveFolderImport") private var recursiveFolderImport: Bool = true
    @AppStorage("outputMode") private var outputMode: OutputMode = .keepOriginal

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
                ContentUnavailableView {
                        Label("No files selected", systemImage: "tray.and.arrow.down.fill")
                    } description: {
                        descriptionText.lineLimit(1)
                    }
                    .background(Color(uiColor: UIColor.systemGroupedBackground))
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
                .alert("Permission required", isPresented: $showPermissionAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Select folder") {
                        isPermissionPickerPresented = true
                    }
                } message: {
                    if missingFolderURL?.path == "GLOBAL_OUTPUT_FOLDER" {
                        Text("Please select a default output folder for your compressed files.")
                    } else {
                        Text("To save files alongside the originals, Chisel needs permission to access '\(missingFolderURL?.lastPathComponent ?? "the folder")'. Please select it in the next screen to grant access.")
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
                // sheet definition for global logs
                .sheet(isPresented: $showGlobalLogs) {
                    NavigationStack {
                        FileInspectorView(file: nil, allLogs: viewModel.logs)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {

                                    Button(role: .cancel) {
                                        showGlobalLogs = false
                                    } label: {
                                        Image(systemName: "xmark")
                                    }

                                }
                            }
                    }
                    .presentationDragIndicator(.visible)
                }
                .safeAreaInset(edge: .bottom) {
                    Button(action: {
                        if let missingDir = viewModel.findMissingPermissionDirectory(for: outputMode) {
                            missingFolderURL = missingDir
                            showPermissionAlert = true
                        } else {
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
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isStopping {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Stopping threads...")
                            } else if viewModel.isImporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Importing files...")
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
                                (viewModel.isImporting ? Color.accentColor.opacity(0.6) :
                                    (viewModel.isProcessing ? Color.red :
                                        (!viewModel.canStartProcessing ? Color.gray : Color.accentColor))))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding()
                    }
                    .disabled(viewModel.isStopping || (!viewModel.canStartProcessing && !viewModel.isProcessing))
                    .fileImporter(
                        isPresented: $isPermissionPickerPresented,
                        allowedContentTypes: [.folder],
                        allowsMultipleSelection: false
                    ) { result in
                        switch result {
                        case .success(let urls):
                            guard let url = urls.first else { return }

                            if missingFolderURL?.path == "GLOBAL_OUTPUT_FOLDER" {
                                viewModel.saveBookmark(for: url)
                            } else {
                                if url.startAccessingSecurityScopedResource() {
                                    viewModel.sessionAuthorizedFolders.insert(url)
                                }
                            }
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
                        case .failure(let error):
                            print("PERMISSION IMPORT FAILED: \(error)")
                        }
                    }
                    .fileDialogDefaultDirectory(missingFolderURL)
                }
                if !viewModel.unsupportedURLs.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach($viewModel.unsupportedURLs, id: \.self) { url in
                                let realUrl = url.wrappedValue
                                HStack {
                                    let category = FileCategory.category(for: realUrl.pathExtension)

                                    Image(systemName: category.iconName)
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(.gray)

                                    Text(realUrl.lastPathComponent)
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)

                                    Spacer()

                                    Text("Unsupported")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.yellow)
                                Text("\(viewModel.unsupportedURLs.count) unsupported files skipped")
                                    .font(.headline)
                            }
                        }
                    }
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

#Preview("Populated list - Light mode") {
    let mockViewModel = ChiselViewModel()

    var containerFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Documents/Report_Annuale_2026.pdf"),
        tempURL: URL(fileURLWithPath: "/tmp/Report_Annuale_2026.pdf"),
        status: .processing,
        size: 15_400_000,
        originalExtension: "pdf"
    )

    var child1 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/image_1.png"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/image_1.png"),
        status: .completed(URL(fileURLWithPath: "/tmp/extracted/image_1_compressed.png")),
        size: 4_200_000,
        originalExtension: "png"
    )
    child1.sizeAfter = 1_150_000

    let child2 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/font_logo.ttf"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/font_logo.ttf"),
        status: .noGain,
        size: 450_000,
        originalExtension: "ttf"
    )

    let child3 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/image_2.png"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/image_2.png"),
        status: .processing,
        size: 2_800_000,
        originalExtension: "png"
    )

    containerFile.children = [child1, child2, child3]

    let pendingFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Downloads/Archivio_Foto_Vacanze.zip"),
        tempURL: URL(fileURLWithPath: "/tmp/Archivio_Foto_Vacanze.zip"),
        status: .pending,
        size: 150_000_000,
        originalExtension: "zip"
    )

    let errorFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Desktop/video_presentazione.mp4"),
        tempURL: URL(fileURLWithPath: "/tmp/video_presentazione.mp4"),
        status: .error("Formato non supportato dal motore"),
        size: 85_000_000,
        originalExtension: "mp4"
    )

    mockViewModel.items = [containerFile, pendingFile, errorFile]
    mockViewModel.unsupportedURLs = [URL(fileURLWithPath: "/Users/mario/Desktop/video_presentazione.mp4")]

    return CompressView(viewModel: mockViewModel)
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    CompressView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

#Preview("Populated list - Dark mode") {
    let mockViewModel = ChiselViewModel()

    var containerFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Documents/Fatture_Q1.pdf"),
        tempURL: URL(fileURLWithPath: "/tmp/Fatture_Q1.pdf"),
        status: .completed(URL(fileURLWithPath: "/tmp/Fatture_Q1_compressed.pdf")),
        size: 8_200_000,
        originalExtension: "pdf"
    )
    containerFile.sizeAfter = 3_100_000

    var child1 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/scan_01.jpeg"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/scan_01.jpeg"),
        status: .completed(URL(fileURLWithPath: "/tmp/extracted/scan_01_compressed.jpeg")),
        size: 4_100_000,
        originalExtension: "jpeg"
    )
    child1.sizeAfter = 1_500_000

    var child2 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/scan_02.jpeg"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/scan_02.jpeg"),
        status: .completed(URL(fileURLWithPath: "/tmp/extracted/scan_02_compressed.jpeg")),
        size: 4_100_000,
        originalExtension: "jpeg"
    )
    child2.sizeAfter = 1_600_000

    containerFile.children = [child1, child2]

    let stoppedFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Downloads/Backup_Sito.tar.gz"),
        tempURL: URL(fileURLWithPath: "/tmp/Backup_Sito.tar.gz"),
        status: .stopped,
        size: 1_050_000_000,
        originalExtension: "gz"
    )

    mockViewModel.items = [containerFile, stoppedFile]

    return CompressView(viewModel: mockViewModel)
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

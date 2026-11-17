import SwiftUI
import UniformTypeIdentifiers
import SwiftData

// navigation sections
enum NavigationSection: String, Hashable {
    case compression
    case stats
    case settings
    case about
}

struct MainNavigationContainerView: View {
    @State private var viewModel = ChiselViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    // navigation state
    @State private var selectedSection: NavigationSection? = .compression

    // content state
    @State private var selectedFileID: UUID?
    @State private var isInspectorPresented = false
    @State private var isImporterPresented = false
    @State private var missingFolderURL: URL?
    @State private var showPermissionAlert = false
    @State private var isDryRunPending = false

    // app settings for compression
    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("threads") private var threads: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    @AppStorage("hideUnsupported") private var hideUnsupported: Bool = true
    @AppStorage("recursiveFolderImport") private var recursiveFolderImport: Bool = true
    @AppStorage("outputMode") private var outputMode: OutputMode = .keepOriginal

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // sidebar
            List(selection: $selectedSection) {
                NavigationLink(value: NavigationSection.compression) {
                    Label("Compress", systemImage: "rectangle.compress.vertical")
                }
                NavigationLink(value: NavigationSection.stats) {
                    Label("Statistics", systemImage: "chart.bar")
                }
                Divider()
                NavigationLink(value: NavigationSection.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                NavigationLink(value: NavigationSection.about) {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Chisel")

        } detail: {
            switch selectedSection {
            case .compression:
                CompressionListView(viewModel: viewModel, selectedFileID: $selectedFileID, isInspectorPresented: $isInspectorPresented)
                    .navigationTitle("Chisel")
                    .toolbar {
                        if !(viewModel.items.isEmpty) {
                            if selectedFileID != nil {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: {
                                        guard let selectedID = selectedFileID,
                                              let index = viewModel.items.firstIndex(where: { $0.id == selectedID }) else { return }

                                        withAnimation {
                                            viewModel.removeItems(at: IndexSet(integer: index))
                                            selectedFileID = nil
                                        }

                                    }) {
                                        Label("Clear", systemImage: "document.on.trash")
                                    }
                                    .disabled(viewModel.isProcessing)
                                }
                            } else {
                                ToolbarItem(placement: .automatic) {
                                    Button(action: {
                                        withAnimation {
                                            viewModel.clearItems()
                                        }
                                    }) {
                                        Label("Clear all", systemImage: "trash")
                                    }
                                    .disabled(viewModel.isProcessing || viewModel.isImporting)
                                }
                            }
                        }
                        ToolbarItem(placement: .automatic) {
                            Button(action: { isImporterPresented.toggle() }) {
                                Label("Add Files", systemImage: "plus")
                            }
                            .disabled(viewModel.isProcessing || viewModel.isImporting)
                        }
                        if !viewModel.items.isEmpty {
                            // combined start/stop button handling isStopping state
                            ToolbarItem(placement: .automatic) {
                                if viewModel.isProcessing || viewModel.isStopping || viewModel.isImporting {
                                    Button(action: {
                                        if viewModel.isProcessing {
                                            viewModel.stopProcessing()
                                        }
                                    }) {
                                        if viewModel.isStopping || viewModel.isImporting {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Label("Stop", systemImage: "stop.fill")
                                        }
                                    }
                                    .disabled(viewModel.isStopping)
                                } else {
                                    Menu {
                                        Button(action: {
                                            startOrRequestPermission(dryRun: true)
                                        }) {
                                            Label("Simulate only (Dry Run)", systemImage: "magnifyingglass")
                                        }
                                    } label: {
                                        Label("Start", systemImage: "play.fill")
                                    } primaryAction: {
                                        startOrRequestPermission(dryRun: false)
                                    }
                                    .disabled(!viewModel.canStartProcessing)
                                }
                            }
                            ToolbarItem(placement: .automatic) {
                                Button(action: { isInspectorPresented.toggle() }) {
                                    Label("Inspector", systemImage: "sidebar.right")
                                }
                            }
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
                            print("file import failed: \(error)")
                        }
                    }
            case .stats:
                StatsDashboardView()
            case .settings:
                SettingsView(viewModel: viewModel)
            case .about:
                AboutView(viewModel: viewModel)
            case .none:
                Text("Select a section from the sidebar")
            }
        }
        .inspector(isPresented: Binding(get: {
            return isInspectorPresented && selectedSection == .compression
        }, set: { newValue in
            isInspectorPresented = newValue
        }), content: {
            if let selectedID = selectedFileID,
               let file = viewModel.findItem(with: selectedID) {
                FileInspectorView(
                    file: file,
                    allLogs: viewModel.logs,
                    showsToolbarAction: selectedSection == .compression
                )
            } else {
                ContentUnavailableView("No selection", systemImage: "info.circle")
            }
        })
        .if(selectedSection == .compression, transform: { view in
            view.dropDestination(for: URL.self) { items, _ in
                viewModel.addFiles(urls: items, recursive: recursiveFolderImport)
                return true
            }
        })
        .alert("Permission required", isPresented: $showPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Select folder") {
                grantAccessAndRetry()
            }
        } message: {
            if missingFolderURL?.path == "GLOBAL_OUTPUT_FOLDER" {
                Text("Please select a default output folder for your compressed files.")
            } else {
                Text("To save files alongside the originals, Chisel needs permission to access '\(missingFolderURL?.lastPathComponent ?? "the folder")'. Please select it in the next screen to grant access.")
            }
        }
    }

    // checks output-folder/write permissions before starting a batch; if something
    // is missing, prompts the user instead of letting finalizeFile fail per-file later.
    private func startOrRequestPermission(dryRun: Bool) {
        isDryRunPending = dryRun
        if let missingDir = viewModel.findMissingPermissionDirectory(for: outputMode) {
            missingFolderURL = missingDir
            showPermissionAlert = true
        } else {
            Task {
                await viewModel.startProcessing(
                    iterations: iterations,
                    iterationsLarge: iterationsLarge,
                    threads: threads,
                    hideUnsupported: hideUnsupported,
                    outputMode: outputMode,
                    dryRun: dryRun,
                    context: modelContext
                )
            }
        }
    }

    private func grantAccessAndRetry() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if missingFolderURL?.path == "GLOBAL_OUTPUT_FOLDER" {
            panel.message = String(localized: "Select the output directory for compressed files")
        } else {
            panel.directoryURL = missingFolderURL
            if let folderName = missingFolderURL?.lastPathComponent {
                panel.message = String(localized: "Grant access to '\(folderName)'")
            } else {
                panel.message = String(localized: "Grant access to this folder")
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if missingFolderURL?.path == "GLOBAL_OUTPUT_FOLDER" {
            viewModel.saveBookmark(for: url)
        } else if url.startAccessingSecurityScopedResource() {
            viewModel.sessionAuthorizedFolders.insert(url)
        }

        Task {
            await viewModel.startProcessing(
                iterations: iterations,
                iterationsLarge: iterationsLarge,
                threads: threads,
                hideUnsupported: hideUnsupported,
                outputMode: outputMode,
                dryRun: isDryRunPending,
                context: modelContext
            )
        }
    }
}

#Preview("Light mode") {
    MainNavigationContainerView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    MainNavigationContainerView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

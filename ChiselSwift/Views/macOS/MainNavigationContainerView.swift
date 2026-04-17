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
    
    // app settings for compression
    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("threads") private var threads: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    @AppStorage("hideUnsupported") private var hideUnsupported: Bool = true
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // sidebar
            List(selection: $selectedSection) {
                NavigationLink(value: NavigationSection.compression) {
                    Label("Compress", systemImage: "rectangle.compress.vertical")
                }
                NavigationLink(value: NavigationSection.stats) {
                    Label("Statistics", systemImage: "chart.bar.xaxis")
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
                CompressionListView(viewModel: viewModel, selectedFileID: $selectedFileID)
                    .navigationTitle("Chisel")
                    .toolbar {
                        if !(viewModel.items.isEmpty) {
                            ToolbarItem(placement: .automatic) {
                                Button(action: { viewModel.clearItems() }) {
                                    Label("Clear", systemImage: "trash")
                                }
                                .disabled(viewModel.isProcessing || viewModel.items.isEmpty)
                            }
                        }
                        ToolbarItem(placement: .automatic) {
                            Button(action: { isImporterPresented.toggle() }) {
                                Label("Add Files", systemImage: "plus")
                            }
                            .disabled(viewModel.isProcessing)
                        }
                        if (!viewModel.items.isEmpty) {
                            ToolbarItem(placement: .automatic) {
                                Button(action: { viewModel.stopProcessing() }) {
                                    Label("Stop", systemImage: "stop.fill")
                                }
                                .disabled(!viewModel.isProcessing)
                            }
                            ToolbarItem(placement: .automatic) {
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
                                    Label("Start", systemImage: "play.fill")
                                }
                                .disabled(!viewModel.canStartProcessing)
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
                    .dropDestination(for: URL.self) { items, location in
                        viewModel.addFiles(urls: items)
                        return true
                    }
            case .stats:
                StatsDashboardView()
            case .settings:
                SettingsView()
            case .about:
                AboutView()
            case .none:
                Text("Select a section from the sidebar")
            }
        }
        .inspector(isPresented: Binding(get: {
            return isInspectorPresented && selectedSection == .compression
        }, set: { _ in
            
        }), content: {
            FileInspectorView(file: viewModel.items.first(where: { $0.id == selectedFileID }),
                              allLogs: viewModel.logs
            )
        })
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

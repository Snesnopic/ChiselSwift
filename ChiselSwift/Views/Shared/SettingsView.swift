import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @AppStorage("verifyChecksums") private var verifyChecksums: Bool = false
    @AppStorage("threads") private var threads: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    @AppStorage("hideUnsupported") private var hideUnsupported: Bool = true
    @AppStorage("recursiveFolderImport") private var recursiveFolderImport: Bool = true
    @AppStorage("outputMode") private var outputMode: OutputMode = .keepOriginal
    @AppStorage("outputFolderBookmark") private var outputFolderBookmark: Data?

    @State private var isFolderPickerPresented = false

    @State private var showAdvancedSettings: Bool = false

    private let maxSystemThreads = max(1, ProcessInfo.processInfo.activeProcessorCount)

    // description based on the current output mode
    private var outputModeDescription: String {
        let mode = outputMode.rawValue.lowercased()
        if mode.contains("overwrite") {
            return "Replaces the original files with the compressed versions. This action is destructive."
        } else if mode.contains("folder") || mode.contains("directory") {
            return "Saves the compressed files into the selected destination directory, leaving originals intact."
        } else {
            return "Creates a separate copy of the compressed file alongside the original."
        }
    }

    private var outputFolderURL: URL? {
        guard let data = outputFolderBookmark else { return nil }
        var isStale = false
#if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
#else
        let options: URL.BookmarkResolutionOptions = []
#endif
        return try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
#if os(macOS)
private func selectFolder() {
    let panel = NSOpenPanel()
    panel.canCreateDirectories = true
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Select the output directory for compressed files"

    if panel.runModal() == .OK, let url = panel.url {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            outputFolderBookmark = bookmark
        } catch {
            print("FAILED TO CREATE BOOKMARK: \(error)")
        }
    }
}
#endif
    @State private var viewModel = ChiselViewModel()
    var body: some View {
        NavigationStack {
            Form {
#if !os(macOS)
                Section {
                    NavigationLink(destination: AboutView(viewModel: viewModel)) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Color.accentColor)
                            Text("About Chisel")
                                .foregroundStyle(.primary)
                        }
                    }
                }
#endif
                // MARK: - General options
                Section {
                    Picker("Output mode", selection: $outputMode) {
                        ForEach(OutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if outputMode == .outputFolder {
                        HStack {
                            Text("Destination:")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(outputFolderURL != nil ? outputFolderURL!.displayFolderName : "Choose folder...") {
                                #if os(macOS)
                                selectFolder()
                                #else
                                isFolderPickerPresented = true
                                #endif
                            }
                        }
                        if let path = outputFolderURL {
                            Text(path.userFriendlyPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .onAppear {
                                    print(path)
                                }
                        }
                    }

                } header: {
                    Text("General options")
                } footer: {
                    Text(outputModeDescription)
                }

                Section {
                    Toggle("Preserve file metadata", isOn: $preserveMetadata)
                } footer: {
                    Text("Keeps EXIF, XMP, color profiles, and timestamps. Disabling this yields slightly better compression but strips most non-essential data.")
                }

                Section {
                    Toggle("Verify data integrity", isOn: $verifyChecksums)
                } footer: {
                    Text("Perform an extra check after each compression to ensure the content of the modified file perfectly matches the original file. Guarantees that your files don't degrade in quality, but makes processing slower.")
                }

                Section {
                    Toggle("Hide unsupported subfiles", isOn: $hideUnsupported)
                } footer: {
                    Text("Many container files, such as PDFs, contain a lot of internal files that can't be processed. This option hides these files.")
                }

                Section {
                    Toggle("Recursive folder import", isOn: $recursiveFolderImport)
                } footer: {
                    Text("When importing a folder, all files in subfolders will be added.")
                }

                // MARK: - System Resources
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Active threads")
                            Spacer()
                            Text("\(threads)")
                        }
                        Slider(
                            value: $threads.asDouble,
                            in: 1...Double(maxSystemThreads),
                            step: 1
                        )
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Warning: using all threads of your system will make it unresponsive!")
                                .font(.caption)
                        }
                        .opacity((threads == maxSystemThreads) ? 1 : 0)
                        .foregroundStyle(.yellow)
                    }
                } header: {
                    Text("System resources")
                } footer: {
                    Text("How many files to process in parallel. More threads will use more CPU but can also make the system unresponsive until all files are processed.")
                }

                // MARK: - Advanced
                Section {
                    Toggle("Show advanced compression parameters", isOn: $showAdvancedSettings)
                } footer: {
                    if !showAdvancedSettings {
                        Text("Expand for fine-tuning some compression related parameters. Incorrectly set values severely degrade performance.")
                    }
                }

                if showAdvancedSettings {
                    Section {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Iterations")
                                Spacer()
                                Text("\(iterations)")
                            }
                            Slider(
                                value: $iterations.asDouble,
                                in: 1...500,
                                step: 1
                            )
                        }

                        VStack(alignment: .leading) {
                            HStack {
                                Text("Iterations on large files")
                                Spacer()
                                Text("\(iterationsLarge)")
                            }
                            Slider(
                                value: $iterationsLarge.asDouble,
                                in: 1...250,
                                step: 1
                            )
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Warning: high iteration count massively increases computational overhead.")
                                    .font(.caption)
                            }
                            .opacity((iterations > 100 || iterationsLarge > 30) ? 1 : 0)
                            .foregroundStyle(.yellow)
                        }
                    } header: {
                        Text("Zopfli / Deflate")
                    } footer: {
                        Text("Amount of iterations of the zopfli algorithm on deflate files (pngs, pdfs, archives).")
                    }

                    Section {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Maximum dictionary tokens")
                                Spacer()
                                Text("\(maxTokens)")
                            }
                            Slider(
                                value: $maxTokens.asDouble,
                                in: 1000...200000,
                                step: 100
                            )
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("Warning: exceeding default tokens can drastically slow down flexigif processing.")
                                    .font(.caption)
                            }
                            .opacity((maxTokens > 10000) ? 1 : 0)
                            .foregroundStyle(.yellow)
                        }
                    } header: {
                        Text("Flexigif")
                    } footer: {
                        Text("Amount of tokens used for flexigif compression.")
                    }

                    // reset defaults button for safety
                    Section {
                        Button(role: .destructive) {
                            iterations = 15
                            iterationsLarge = 5
                            maxTokens = 10000
                        } label: {
                            Text("Reset advanced parameters to defaults")
                        }
                    }
                }
            }
#if !os(macOS)
            .fileImporter(
                isPresented: $isFolderPickerPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let bookmarkData = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                            outputFolderBookmark = bookmarkData
                        }
                    }
                }
            }
#endif
            .navigationTitle("Settings")
#if os(macOS)
            .formStyle(.grouped)
#endif
        }
#if os(macOS)
        .padding()
        .frame(width: 600)
#endif
    }
}

#Preview("Light mode") {
    SettingsView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    SettingsView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @AppStorage("verifyChecksums") private var verifyChecksums: Bool = false
    @AppStorage("threads") private var threads: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    
    private let maxSystemThreads = max(1, ProcessInfo.processInfo.activeProcessorCount)
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Compression Parameters
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
                            Text("Warning: high iteration count may significantly increase processing time! Use at your own risk!")
                                .font(.caption)
                        }
                        .opacity((iterations > 100 || iterationsLarge > 30) ? 1 : 0)
                        .foregroundStyle(.yellow)
                    }
                } header: {
                    Text("Compression parameters")
                } footer: {
                    Text("""
                    Amount of iterations of the zopfli algorithm on DEFLATE files. This affects PNGs, PDFs and some archives.
                    Consider using a lower value for large files as it massively increases computation time.
                    """)
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
                            Text("Warning: exceeding default tokens can drastically slow down processing! Use at your own risk!")
                                .font(.caption)
                        }
                        .opacity((maxTokens > 10000) ? 1 : 0)
                        .foregroundStyle(.yellow)
                    }
                    
                } footer: {
                    Text("""
                    Amount of tokens used for flexigif compression. This affects GIF files.
                    """)
                }
                
                // MARK: - General Options
                Section {
                    Toggle("Preserve file metadata", isOn: $preserveMetadata)
                } header: {
                    Text("General options")
                } footer: {
                    Text("""
                    Keeps EXIF, XMP, color profiles, and timestamps. Disabling this yields slightly better compression but strips most non-essential data.
                    """)
                }
                Section {
                    Toggle("Verify data integrity (checksums)", isOn: $verifyChecksums)
                }  footer: {
                    Text("""
                    Perform a check after each compression to ensure the content of the modified file perfectly matches the original file. Guarantees that your files don't degrade in quality, but makes processing slower.
                    """)
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
                } header : {
                    Text("System resources")
                } footer: {
                    Text("How many files to process in parallel. More threads will use more CPU but can also make the system unresponsive until all files are processed.")
                }
            }
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

#Preview("Light Mode") {
    SettingsView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    SettingsView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

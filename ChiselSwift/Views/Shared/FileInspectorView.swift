import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook

struct FileInspectorView: View {
    let file: FileItem?
    let allLogs: [String]
    var showsToolbarAction: Bool = true

    @State private var quickLookURL: URL?

    var body: some View {
        Group {
            if let file = file {
                VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 12) {
                        previewView(for: file)

                        HStack {
                            Image(systemName: file.typeIconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.blue)

                            Text(file.url.lastPathComponent)
                                .font(.headline)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Format", value: file.originalExtension.uppercased())
                        InfoRow(label: "Original size", value: formatSize(file.size))
                        if let after = file.sizeAfter {
                            InfoRow(label: "New size", value: formatSize(after))
                        }
                    }

                    logTerminalView(logs: file.logs, title: "Process log")

                    Spacer()
                }
                .padding()
            } else {
                // global terminal when no file is selected
                NavigationStack {
                    VStack(alignment: .leading) {

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if allLogs.isEmpty {
                                    Text("No logs generated yet")
                                        .foregroundStyle(.secondary)
                                } else {
                                    logTerminalView(logs: allLogs, title: nil)
                                }
                            }
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)

                            .padding(8)

                            #if !os(macOS)
                            .background(Color(uiColor: UIColor.systemGroupedBackground))
                            #endif
                        }
                        .padding(.horizontal)
                    }
                    .navigationTitle("Global logs")
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                }
            }
        }
        // export button only for macOS
        .toolbar {
#if os(macOS)
            if showsToolbarAction {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: exportLogs) {
                        Label("Export logs", systemImage: "square.and.arrow.up")
                    }
                    .help("Export current logs to .txt")
                    // disabled if there are no logs to export
                    .disabled(file != nil ? file!.logs.isEmpty : allLogs.isEmpty)
                }
            }
#endif
        }
        .quickLookPreview($quickLookURL)
    }

    // tappable thumbnail (image types get an actual preview, everything else a generic
    // icon) that opens the full QuickLook preview - which, unlike AsyncImage, can render
    // PDFs, audio, video and most document formats, not just images.
    @ViewBuilder
    private func previewView(for file: FileItem) -> some View {
        if let previewURL = file.previewURL {
            Button {
                quickLookURL = previewURL
            } label: {
                previewThumbnail(for: file, url: previewURL)
            }
            .buttonStyle(.plain)
        } else {
            // file was cleaned up by the system
            ContentUnavailableView(
                "Preview unavailable",
                systemImage: "eye.slash",
                description: Text("The temporary file has been cleaned up by the system.")
            )
            .frame(maxHeight: 140)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func previewThumbnail(for file: FileItem, url: URL) -> some View {
        Group {
            if let utType = UTType(filenameExtension: file.originalExtension), utType.conforms(to: .image) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else if phase.error != nil {
                        genericPreviewPlaceholder(for: file)
                    } else {
                        ProgressView()
                    }
                }
            } else {
                genericPreviewPlaceholder(for: file)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 140)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 8)
    }

    private func genericPreviewPlaceholder(for file: FileItem) -> some View {
        VStack(spacing: 8) {
            Image(systemName: file.typeIconName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
            Text("Tap to preview")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
        private func logTerminalView(logs: [String], title: LocalizedStringKey?) -> some View {
            VStack(alignment: .leading) {
                if let title = title {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if logs.isEmpty {
                            Text("No log data available")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(logs.enumerated()), id: \.offset) { _, logLine in
                                Text(logLine)
                                    .foregroundStyle(logLine.localizedCaseInsensitiveContains("error") ? .red : .primary)
                            }
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.background)
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, title == nil ? 16 : 0)
        }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

#if os(macOS)
    private func exportLogs() {
        // determine content and filename based on selection
        let content = file?.logs.joined(separator: "\n") ?? self.allLogs.joined(separator: "\n")
        let baseName = file?.url.deletingPathExtension().lastPathComponent ?? "chisel_global_logs"
        let filename = "result_log_\(baseName).txt"

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = String(localized: "Export Logs")
        savePanel.message = String(localized: "Choose where to save the log file")
        savePanel.nameFieldStringValue = filename

        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    print("LOGS EXPORTED TO: \(url.path)")
                } catch {
                    print("FAILED TO EXPORT LOGS: \(error)")
                }
            }
        }
    }
#endif
}

#Preview("Light mode") {
    FileInspectorView(
        file: FileItem(
            url: URL(fileURLWithPath: "/Users/test/Desktop/example.png"),
            tempURL: URL(fileURLWithPath: "/Users/test/Desktop/example.png"),
            status: .pending, size: 1_024_000,
            sizeAfter: 512_000,
            originalExtension: "png",
            logs: [
                "Starting compression…",
                "Compression level: medium",
                "Output written successfully"
            ]
        ), allLogs: []
    )
    .modelContainer(for: CompressionStat.self, inMemory: true)
    .preferredColorScheme(.light)
}

#Preview("No file") {
    FileInspectorView(file: nil, allLogs: ["Prova"])
        .modelContainer(for: CompressionStat.self, inMemory: true)
}

#Preview("Dark mode") {
    FileInspectorView(
        file: FileItem(
            url: URL(fileURLWithPath: "/Users/test/Desktop/example.png"),
            tempURL: URL(fileURLWithPath: "/Users/test/Desktop/example.png"),
            status: .pending, size: 1_024_000,
            sizeAfter: 512_000,
            originalExtension: "png",
            logs: [
                "Starting compression…",
                "Compression level: medium",
                "Output written successfully"
            ]
        ), allLogs: []
    )
    .modelContainer(for: CompressionStat.self, inMemory: true)
    .preferredColorScheme(.dark)
}

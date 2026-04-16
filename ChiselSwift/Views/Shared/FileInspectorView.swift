import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FileInspectorView: View {
    let file: FileItem?
    let allLogs: [String]
    
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
                    
                    VStack(alignment: .leading) {
                        Text("Process log")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                if file.logs.isEmpty {
                                    Text("No log data available")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(file.logs.enumerated()), id: \.offset) { index, logLine in
                                        Text(logLine)
                                            .foregroundStyle(logLine.localizedCaseInsensitiveContains("ERROR") ? .red : .primary)
                                    }
                                }
                            }
                            .font(.system(.caption2, design: .monospaced))
                            .frame(alignment: .leading)
                            .padding(8)
                            .background(.background)
                            .cornerRadius(4)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            } else {
                // global terminal when no file is selected
                VStack(alignment: .leading) {
                    Text("Global logs")
                        .font(.headline)
                        .padding([.top, .horizontal])
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            if allLogs.isEmpty {
                                Text("No logs generated yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(allLogs.enumerated()), id: \.offset) { index, logLine in
                                    Text(logLine)
                                        .foregroundStyle(logLine.localizedCaseInsensitiveContains("ERROR") ? .red : .primary)
                                }
                            }
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.background)
                        .cornerRadius(4)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // dynamically generate a preview if the file is a supported image
    @ViewBuilder
    private func previewView(for file: FileItem) -> some View {
        if let utType = UTType(filenameExtension: file.originalExtension), utType.conforms(to: .image) {
            AsyncImage(url: file.url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 140)
                        .cornerRadius(8)
                } else if phase.error != nil {
                    // silently fail if the image cannot be read locally
                    EmptyView()
                } else {
                    // loading state
                    ProgressView()
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }.font(.caption)
    }
}

#Preview("Light Mode") {
    FileInspectorView(
        file: FileItem(
            url: URL(fileURLWithPath: "/Users/test/Desktop/example.png"),
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

#Preview("Dark Mode") {
    FileInspectorView(
        file: FileItem(
            url: URL(fileURLWithPath: "/Users/test/Desktop/example.png"),
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

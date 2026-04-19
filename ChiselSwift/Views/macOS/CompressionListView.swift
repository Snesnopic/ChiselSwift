import SwiftUI
import SwiftData

struct CompressionListView: View {
    @Bindable var viewModel: ChiselViewModel
    @Binding var selectedFileID: UUID?

    var body: some View {
        if viewModel.items.isEmpty {
            ContentUnavailableView(
                "No files selected",
                systemImage: "tray.and.arrow.down.fill",
                description: Text("Drag and drop files here, or use the add button to start compressing.")
            )
        } else {
            List(viewModel.items, children: \.children, selection: $selectedFileID) { item in
                let isError = isStatusError(item.status)
                HStack(spacing: 14) {
                    // larger icons
                    Image(systemName: item.typeIconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.blue)
                        .symbolRenderingMode(.hierarchical)

                    // text hierarchy
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.url.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 6) {
                            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let children = item.children, !children.isEmpty {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text("\(children.count) files inside")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(item.url.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()
                    if isError {
                        Button {
                            selectedFileID = item.id
                            // open inspector or specific log view
                        } label: {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("View error details")
                    }
                    if let percentage = item.savingPercentage {
                        SavingsBarView(percentage: percentage)
                    }

                    StatusBadgeView(status: item.status)
                }
                .padding(.vertical, 4)
                // dim the row if it yielded no gain or was interrupted
                .opacity((item.status == .noGain || item.status == .stopped) ? 0.5 : 1.0)
                .tag(item.id)
                // context menu
                .contextMenu {
                    Button {
                        revealInFinder(item)
                    } label: {
                        Label("Reveal in Finder", systemImage: "magnifyingglass")
                    }

                    Divider()

                    Button(role: .destructive) {
                        withAnimation {
                            delete(item: item)
                        }
                    } label: {
                        Label("Delete", systemImage: "document.on.trash")
                    }
                    .disabled(viewModel.isProcessing)
                }
            }
            .onDeleteCommand {
                // delete root level items
                guard let selectedID = selectedFileID,
                      let index = viewModel.items.firstIndex(where: { $0.id == selectedID }) else { return }
                withAnimation {
                    selectedFileID = nil
                    viewModel.removeItems(at: IndexSet(integer: index))
                }

            }
            .onKeyPress(.escape) {
                // clear selection
                withAnimation {
                    selectedFileID = nil
                }
                return .handled
            }
        }
    }
    struct SavingsBarView: View {
        let percentage: Double

        var body: some View {
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "-%.1f%%", percentage))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.green)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.gray.opacity(0.2))
                        Capsule()
                            .fill(.green.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(min(percentage / 100, 1.0)))
                    }
                }
            }
        }
    }
    private func isStatusError(_ status: FileItem.ProcessingStatus) -> Bool {
        if case .error = status { return true }
        return false
    }

    // MARK: - Actions

    private func revealInFinder(_ item: FileItem) {
        #if os(macOS)
        let urlToReveal: URL
        // select output file if completed, otherwise original input file
        if case .completed(let outURL) = item.status {
            urlToReveal = outURL
        } else {
            urlToReveal = item.url
        }
        NSWorkspace.shared.activateFileViewerSelecting([urlToReveal])
        #endif
    }

    private func delete(item: FileItem) {
        // delete single row. requires recursive search if subfile deletion is needed later
        if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
            viewModel.removeItems(at: IndexSet(integer: index))
        }
        withAnimation {
            selectedFileID = nil
        }
    }
}

#Preview("Light mode") {
    CompressionListView(viewModel: ChiselViewModel(), selectedFileID: .constant(UUID()))
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    CompressionListView(viewModel: ChiselViewModel(), selectedFileID: .constant(UUID()))
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

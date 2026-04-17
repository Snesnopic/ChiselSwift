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
            .dropDestination(for: URL.self) { items, _ in
                viewModel.addFiles(urls: items)
                return true
            }
        } else {
            List(viewModel.items, children: \.children, selection: $selectedFileID) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.typeIconName)
                        .foregroundStyle(.blue)
                        .frame(width: 20)

                    VStack(alignment: .leading) {
                        Text(item.url.lastPathComponent)
                            .font(.body)

                        // safe display of children count
                        if let children = item.children, !children.isEmpty {
                            Text("\(children.count) files inside")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let percentage = item.savingPercentage {
                        SavingsBarView(percentage: percentage)
                    }

                    StatusBadgeView(status: item.status)
                }
                .opacity(item.status == .noGain ? 0.5 : 1.0)
                .tag(item.id)
            }
            .onDeleteCommand {
                // delete root level items
                guard let selectedID = selectedFileID,
                      let index = viewModel.items.firstIndex(where: { $0.id == selectedID }) else { return }

                viewModel.removeItems(at: IndexSet(integer: index))
            }
            .onKeyPress(.escape) {
                // clear selection
                selectedFileID = nil
                return .handled
            }
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
            .frame(width: 60, height: 4)
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

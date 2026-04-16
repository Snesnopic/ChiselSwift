import SwiftUI
import SwiftData

struct CompressionListView: View {
    @Bindable var viewModel: ChiselViewModel
    @Binding var selectedFileID: UUID?
    
    var body: some View {
        if(viewModel.items.isEmpty) {
            ContentUnavailableView(
                "No files selected",
                systemImage: "tray.and.arrow.down.fill",
                description: Text("Drag and drop files here, or use the add button to start compressing.")
            )
        } else {
            List(viewModel.items, children: \.children, selection: $selectedFileID) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.typeIconName)
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    
                    VStack(alignment: .leading) {
                        Text(item.url.lastPathComponent)
                            .font(.body)
                        if item.children != nil {
                            Text("\(item.children?.count ?? 0) files inside")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // SAVINGS BAR
                    if let percentage = item.savingPercentage {
                        SavingsBarView(percentage: percentage)
                    }
                    
                    StatusBadgeView(status: item.status)
                }
                .opacity(item.status == .noGain ? 0.5 : 1.0)
                .tag(item.id)
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

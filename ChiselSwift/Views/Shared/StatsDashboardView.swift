import SwiftUI
import SwiftData
import Charts

struct StatsDashboardView: View {
    @Query(sort: \CompressionStat.timestamp, order: .reverse) private var stats: [CompressionStat]

    // global metrics
    private var totalSaved: Int64 {
        stats.reduce(0) { $0 + $1.savedBytes }
    }

    private var totalFiles: Int {
        stats.count
    }

    private var largestFile: Int64 {
        stats.max(by: { $0.originalSize < $1.originalSize })?.originalSize ?? 0
    }

    private var biggestSave: Int64 {
        stats.max(by: { $0.savedBytes < $1.savedBytes })?.savedBytes ?? 0
    }

    // chart aggregations
    private var savingsByExtension: [(ext: String, saved: Int64)] {
        let grouped = Dictionary(grouping: stats, by: { $0.fileExtension })
        let mapped = grouped.map { key, value in
            (ext: key.uppercased(), saved: value.reduce(0) { $0 + $1.savedBytes })
        }
        return mapped.sorted { $0.saved > $1.saved }
    }

    var body: some View {
        NavigationStack {
            if stats.isEmpty {
                // native empty state view
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.pie",
                    description: Text("Come back when you'll have compressed some files!")
                )
                .navigationTitle("Statistics")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {

                        // global counter section
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total space saved")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text(totalSaved.formatBytes())
                                .font(.system(size: 54, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.green.gradient)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)

                        // highlights grid
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], alignment: .leading) {
                            StatCardView(title: "Files processed", value: "\(totalFiles)", icon: "doc.on.doc", color: .blue)
                            StatCardView(title: "Largest file", value: largestFile.formatBytes(), icon: "arrow.up.doc", color: .orange)
                            StatCardView(title: "Biggest save", value: biggestSave.formatBytes(), icon: "arrow.down.right.circle", color: .purple)
                        }
                        .padding(.horizontal)

                        // charts section
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 600), spacing: 24)], alignment: .center) {

                            // pie chart: savings by format
                            VStack(alignment: .leading) {
                                Text("Savings by format")
                                    .font(.headline)

                                Chart(savingsByExtension, id: \.ext) { item in
                                    SectorMark(
                                        angle: .value("Saved bytes", item.saved),
                                        innerRadius: .ratio(0.6),
                                        angularInset: 2.0
                                    )
                                    .foregroundStyle(by: .value("Format", item.ext))
                                    .annotation(position: .overlay) {
                                        Text(item.ext)
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(height: 250)
                            }
                            .padding()
                            .background(.background)
                            .cornerRadius(16)
                        }
                        .padding(.horizontal)
                    }
                    .navigationTitle("Statistics")
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

// reusable view for small metric cards
struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title3)
                .bold()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .cornerRadius(12)
    }
}

#Preview("Light mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CompressionStat.self, configurations: config)
    let context = container.mainContext

    // insert mock data for the charts
    let mockData = [
        CompressionStat(fileExtension: "pdf", originalSize: 25_000_000, compressedSize: 15_000_000, durationSeconds: 1.2),
        CompressionStat(fileExtension: "png", originalSize: 8_500_000, compressedSize: 3_200_000, durationSeconds: 0.8),
        CompressionStat(fileExtension: "zip", originalSize: 150_000_000, compressedSize: 95_000_000, durationSeconds: 4.5),
        CompressionStat(fileExtension: "pdf", originalSize: 12_000_000, compressedSize: 8_000_000, durationSeconds: 0.9),
        CompressionStat(fileExtension: "jpeg", originalSize: 4_200_000, compressedSize: 80_000, durationSeconds: 0.3)
    ]

    for stat in mockData {
        context.insert(stat)
    }

    return StatsDashboardView()
        .modelContainer(container)
        .preferredColorScheme(.light)
}

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CompressionStat.self, configurations: config)

    return StatsDashboardView()
        .modelContainer(container)
}

#Preview("Dark mode") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: CompressionStat.self, configurations: config)
    let context = container.mainContext

    // insert mock data for the charts
    let mockData = [
        CompressionStat(fileExtension: "pdf", originalSize: 25_000_000, compressedSize: 15_000_000, durationSeconds: 1.2),
        CompressionStat(fileExtension: "png", originalSize: 8_500_000, compressedSize: 3_200_000, durationSeconds: 0.8),
        CompressionStat(fileExtension: "zip", originalSize: 150_000_000, compressedSize: 95_000_000, durationSeconds: 4.5),
        CompressionStat(fileExtension: "pdf", originalSize: 12_000_000, compressedSize: 8_000_000, durationSeconds: 0.9),
        CompressionStat(fileExtension: "jpeg", originalSize: 4_200_000, compressedSize: 1_100_000, durationSeconds: 0.3)
    ]

    for stat in mockData {
        context.insert(stat)
    }

    return StatsDashboardView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

import SwiftUI
import SwiftData
import Charts

struct StatsDashboardView: View {
    @Environment(\.colorScheme) var colorScheme: ColorScheme
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
                ContentUnavailableView(
                    "No statistics yet",
                    systemImage: "chart.pie",
                    description: Text("Come back when you'll have compressed some files!")
                )
                .navigationTitle("Statistics")
            } else {
                ScrollView {
                    VStack(spacing: 16) {

                        // bento box section
                        ViewThatFits {
                            // wide layout for macos/ipad
                            HStack(spacing: 16) {
                                HeroStatCard(title: "Total space saved", value: totalSaved.formatBytes(), color: .green)

                                VStack(spacing: 16) {
                                    HStack(spacing: 16) {
                                        StatCardView(title: "Files", value: "\(totalFiles)", icon: "doc.on.doc", color: .blue)
                                        StatCardView(title: "Largest", value: largestFile.formatBytes(), icon: "arrow.up.doc", color: .orange)
                                    }
                                    StatCardView(title: "Biggest save", value: biggestSave.formatBytes(), icon: "arrow.down.right.circle", color: .purple)
                                }
                                .frame(minWidth: 320)
                            }

                            // narrow layout for ios portrait
                            VStack(spacing: 16) {
                                HeroStatCard(title: "Total space saved", value: totalSaved.formatBytes(), color: .green)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    StatCardView(title: "Files", value: "\(totalFiles)", icon: "doc.on.doc", color: .blue)
                                    StatCardView(title: "Largest", value: largestFile.formatBytes(), icon: "arrow.up.doc", color: .orange)
                                }

                                StatCardView(title: "Biggest save", value: biggestSave.formatBytes(), icon: "arrow.down.right.circle", color: .purple)
                            }
                        }

                        FormatChartCard(data: savingsByExtension)
                    }
                    .padding()
                }
                .navigationTitle("Statistics")
            }
        }
    }
}

// MARK: - Components

struct HeroStatCard: View {
    let title: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundStyle(color.gradient)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // match the exact height of two small cards + spacing (approx 180-200)
        .frame(height: 190)
        .if(colorScheme == .dark, transform: { view in
            view.background(.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })
        .if(colorScheme == .light, transform: { view in
            view.background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })

        .shadow(color: .primary.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct StatCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.title2)
                .bold()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        .if(colorScheme == .dark, transform: { view in
            view.background(.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })
        .if(colorScheme == .light, transform: { view in
            view.background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })
        .shadow(color: .primary.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct FormatChartCard: View {
    let data: [(ext: String, saved: Int64)]
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Savings by format")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart(data, id: \.ext) { item in
                BarMark(
                    x: .value("saved", item.saved),
                    y: .value("format", item.ext)
                )
                .foregroundStyle(by: .value("format", item.ext))
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(item.saved.formatBytes())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            // scale height dynamically based on the number of formats processed
            .frame(height: max(120, CGFloat(data.count * 40)))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .if(colorScheme == .dark, transform: { view in
            view.background(.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })
        .if(colorScheme == .light, transform: { view in
            view.background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        })
        .shadow(color: .primary.opacity(0.15), radius: 8, x: 0, y: 4)
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
        .modelContainer(container)
        .preferredColorScheme(.dark)
}

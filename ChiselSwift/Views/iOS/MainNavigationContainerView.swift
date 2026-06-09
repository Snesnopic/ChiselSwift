import SwiftUI
import SwiftData

struct MainNavigationContainerView: View {
    @State var viewModel = ChiselViewModel()
    var body: some View {
        TabView {
            CompressView(viewModel: viewModel)
                .tabItem {
                    Label("Compress", image: "compress.fill")
                }

            StatsDashboardView()
                .tabItem {
                    Label("Statistics", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

        }
    }
}

#Preview("Light mode") {
    let mockViewModel = ChiselViewModel()

    var containerFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Documents/Report_Annuale_2026.pdf"),
        tempURL: URL(fileURLWithPath: "/tmp/Report_Annuale_2026.pdf"),
        status: .processing,
        size: 15_400_000,
        originalExtension: "pdf"
    )

    var child1 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/image_1.png"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/image_1.png"),
        status: .completed(URL(fileURLWithPath: "/tmp/extracted/image_1_compressed.png")),
        size: 4_200_000,
        originalExtension: "png"
    )
    child1.sizeAfter = 1_150_000

    let child2 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/font_logo.ttf"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/font_logo.ttf"),
        status: .noGain,
        size: 450_000,
        originalExtension: "ttf"
    )

    let child3 = FileItem(
        url: URL(fileURLWithPath: "/tmp/extracted/image_2.png"),
        tempURL: URL(fileURLWithPath: "/tmp/extracted/image_2.png"),
        status: .processing,
        size: 2_800_000,
        originalExtension: "png"
    )

    containerFile.children = [child1, child2, child3]

    let pendingFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Downloads/Archivio_Foto_Vacanze.zip"),
        tempURL: URL(fileURLWithPath: "/tmp/Archivio_Foto_Vacanze.zip"),
        status: .pending,
        size: 150_000_000,
        originalExtension: "zip"
    )

    let errorFile = FileItem(
        url: URL(fileURLWithPath: "/Users/mario/Desktop/video_presentazione.mp4"),
        tempURL: URL(fileURLWithPath: "/tmp/video_presentazione.mp4"),
        status: .error("Formato non supportato dal motore"),
        size: 85_000_000,
        originalExtension: "mp4"
    )

    mockViewModel.items = [containerFile, pendingFile, errorFile]
    mockViewModel.unsupportedURLs = [URL(fileURLWithPath: "/Users/mario/Desktop/video_presentazione.mp4")]
    return MainNavigationContainerView(viewModel: mockViewModel)
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    MainNavigationContainerView()
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

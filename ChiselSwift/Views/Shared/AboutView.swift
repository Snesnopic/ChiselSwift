import SwiftUI
import SwiftData
import ChiselKit

struct AboutView: View {
    @Bindable var viewModel: ChiselViewModel

    var body: some View {
        // Aggiungiamo uno ScrollView perché espandendo la lista
        // lo spazio verticale crescerà parecchio
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let copyrightString = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "Copyright © 2026 Snesnopic"
        let extensions = viewModel.supportedExtensions
        let groupedFormats: [FileCategory: [String]] = Dictionary(grouping: extensions) { ext in
            FileCategory.category(for: ext)
        }

        ScrollView {
            VStack(spacing: 24) {

                AppIconView()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)

                VStack(spacing: 4) {
                    Text("Chisel")
                        .font(.system(size: 28, weight: .bold))

                    Text("Version \(appVersion)")
                        .font(.body)
                    Text("Chisel \(viewModel.libraryVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Link("Chisel engine", destination: URL(string: "https://github.com/Snesnopic/chisel")!)
                    Link("Chisel GUI", destination: URL(string: "https://github.com/Snesnopic/ChiselSwift")!)
                    HStack(spacing: 0) {
                        Text("App icon by ")
                        Link("Mahary Esposito", destination: URL(string: "https://www.behance.net/mychan1")!)
                    }
                }
                .font(.callout)
                .padding(.vertical, 8)

                Section {
                    Link(destination: URL(string: "https://www.icloud.com/shortcuts/e288211f8952436098784f107df3083c")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.2.layers.3d.top.filled")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Automate with Shortcuts")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Chisel provides App Intents to compress your files silently in the background or right from the Finder context menu.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: - Supported Formats Disclosure Group
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedFormats.keys.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { category in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(category.displayName, systemImage: category.iconName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                if let extList = groupedFormats[category]?.sorted() {
                                    let text = extList.joined(separator: ", ")
                                    Text(text)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()
                            }
                        }
                    }
                    .padding(.top, 12)
                    // Disallineamento corretto a sinistra del contenuto interno
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.blue)
                        Text("Supported formats (\(extensions.count))")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .padding()
                #if !os(macOS)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                #endif
                Text(copyrightString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
        .frame(minWidth: 300, minHeight: 350)
        #if !os(macOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
        .task {
            // fetch the version asynchronously when the view appears
            viewModel.fetchVersion()
        }
    }
}

#Preview("Light mode") {
    AboutView(viewModel: ChiselViewModel())
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    AboutView(viewModel: ChiselViewModel())
        .modelContainer(for: CompressionStat.self, inMemory: true)
        .preferredColorScheme(.dark)
}

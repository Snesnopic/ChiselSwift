import SwiftUI
import ChiselKit

struct SupportedFormatsView: View {
    @State private var extensions: [String] = []

    var groupedFormats: [FileCategory: [String]] {
        Dictionary(grouping: extensions) { ext in
            FileCategory.category(for: ext)
        }
    }

    var body: some View {
        List {
            ForEach(groupedFormats.keys.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { category in
                Section {
                    if let extList = groupedFormats[category]?.sorted() {
                        Text(extList.joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label(category.displayName, systemImage: category.iconName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .task {
            extensions = await Chisel().supportedExtensions
        }
        .navigationTitle("Supported formats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview ("Light mode") {
    SupportedFormatsView()
        .preferredColorScheme(.light)
}

#Preview ("Dark mode") {
    SupportedFormatsView()
        .preferredColorScheme(.dark)
}

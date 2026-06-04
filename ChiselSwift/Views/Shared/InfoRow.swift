import SwiftUI

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

#Preview ("Light mode") {
    InfoRow(label: "Prova", value: "Prova 2")
        .preferredColorScheme(.light)
}

#Preview ("Dark mode") {
    InfoRow(label: "Prova", value: "Prova 2")
        .preferredColorScheme(.dark)
}

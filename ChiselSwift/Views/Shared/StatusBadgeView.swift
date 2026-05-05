import SwiftUI
internal import System

struct StatusBadgeView: View {
    let status: FileItem.ProcessingStatus

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.gray)

        case .processing:
            ProgressView()
                .controlSize(.small)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

        case .noGain:
            Image(systemName: "equal.circle.fill")
                .foregroundColor(.blue)

        case .skipped:
            Image(systemName: "forward.end.circle.fill")
                .foregroundColor(.yellow)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

        case .stopped:
            Image(systemName: "clock")
                .foregroundColor(.gray)
        }
    }
}

#Preview("Light Mode") {
    VStack(spacing: 16) {
        StatusBadgeView(status: .pending)
        StatusBadgeView(status: .processing)
        StatusBadgeView(status: .completed(URL(filePath: "")!))
        StatusBadgeView(status: .noGain)
        StatusBadgeView(status: .skipped)
        StatusBadgeView(status: .error(""))
        StatusBadgeView(status: .stopped)
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: 16) {
        StatusBadgeView(status: .pending)
        StatusBadgeView(status: .processing)
        StatusBadgeView(status: .completed(URL(filePath: "")!))
        StatusBadgeView(status: .noGain)
        StatusBadgeView(status: .skipped)
        StatusBadgeView(status: .error(""))
        StatusBadgeView(status: .stopped)
    }
    .padding()
    .preferredColorScheme(.dark)
}

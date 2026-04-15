import SwiftUI

struct SettingsView: View {
    @AppStorage("iterations") private var iterations: Int = 15
    @AppStorage("iterationsLarge") private var iterationsLarge: Int = 5
    @AppStorage("maxTokens") private var maxTokens: Int = 10000
    @AppStorage("preserveMetadata") private var preserveMetadata: Bool = true
    @AppStorage("verifyChecksums") private var verifyChecksums: Bool = false
    @AppStorage("threads") private var threads: Int = 4
    
    private let maxSystemThreads = max(1, ProcessInfo.processInfo.activeProcessorCount)
    
    var body: some View {
        Form {
            Section("Compression Parameters") {
                VStack(alignment: .leading) {
                    Text("Iterations: \(iterations)")
                    Slider(
                        value: Binding(get: { Double(iterations) }, set: { iterations = Int($0) }),
                        in: 1...500,
                        step: 1
                    )
                    if iterations > 100 {
                        Text("Warning: high iteration count may significantly increase processing time")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Large file iterations: \(iterationsLarge)")
                    Slider(
                        value: Binding(get: { Double(iterationsLarge) }, set: { iterationsLarge = Int($0) }),
                        in: 1...250,
                        step: 1
                    )
                    if iterationsLarge > 50 {
                        Text("Warning: high iteration count for large files may cause severe slowdowns")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Maximum dictionary tokens: \(maxTokens)")
                    Slider(
                        value: Binding(get: { Double(maxTokens) }, set: { maxTokens = Int($0) }),
                        in: 1000...100000,
                        step: 1000
                    )
                    if maxTokens > 10000 {
                        Text("Warning: exceeding default tokens can drastically slow down processing")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Section("General Options") {
                Toggle("Preserve file metadata", isOn: $preserveMetadata)
                Toggle("Verify data integrity (checksums)", isOn: $verifyChecksums)
            }
            
            Section("System Resources") {
                VStack(alignment: .leading) {
                    Text("Active threads: \(threads)")
                    Slider(
                        value: Binding(get: { Double(threads) }, set: { threads = Int($0) }),
                        in: 1...Double(maxSystemThreads),
                        step: 1
                    )
                }
            }
        }
        #if os(macOS)
        .padding()
        .frame(width: 400)
        #endif
    }
}

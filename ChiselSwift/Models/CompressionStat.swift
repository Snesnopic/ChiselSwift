
import Foundation
import SwiftData

@Model
final class CompressionStat {
    var id: UUID
    var timestamp: Date
    var fileExtension: String
    var originalSize: Int64
    var compressedSize: Int64
    var durationSeconds: Double
    
    init(fileExtension: String, originalSize: Int64, compressedSize: Int64, durationSeconds: Double) {
        self.id = UUID()
        self.timestamp = Date()
        self.fileExtension = fileExtension.lowercased()
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.durationSeconds = durationSeconds
    }
    
    // calculated properties not persisted in the database
    @Transient var savedBytes: Int64 {
        originalSize - compressedSize
    }
    
    @Transient var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return (Double(savedBytes) / Double(originalSize)) * 100
    }
}

import Foundation
import SwiftData

/// A persistent SwiftData model representing the statistics of a single successful compression operation.
@Model
final class CompressionStat {
    /// Unique identifier for the record.
    var id: UUID
    
    /// The date and time when the compression was completed.
    var timestamp: Date
    
    /// The original file extension in lowercase.
    var fileExtension: String
    
    /// Original file size in bytes before compression.
    var originalSize: Int64
    
    /// Final file size in bytes after successful compression.
    var compressedSize: Int64
    
    /// The time taken to process the file, in seconds.
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
    
    /// Total bytes saved by the compression.
    @Transient var savedBytes: Int64 {
        originalSize - compressedSize
    }

    /// The percentage of space saved, from 0 to 100.
    @Transient var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return (Double(savedBytes) / Double(originalSize)) * 100
    }
}

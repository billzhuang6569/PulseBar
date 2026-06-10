import Foundation

enum MetricFormatter {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func bytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(max(0, bytes)))
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        "\(bytes(bytesPerSecond))/s"
    }
}

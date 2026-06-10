import Foundation

enum MetricFormatter {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func compactPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))"
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

    static func compactSpeed(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fG", value / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:
            return "\(Int(value / 1_000))K"
        default:
            return "\(Int(value))B"
        }
    }
}

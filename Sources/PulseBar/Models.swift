import Foundation
import SwiftUI

enum MetricKind: String, CaseIterable, Identifiable {
    case memory
    case network
    case disk
    case cpu
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: "内存"
        case .network: "网速"
        case .disk: "硬盘"
        case .cpu: "CPU"
        case .battery: "电池"
        }
    }

    var compactTitle: String {
        switch self {
        case .memory: "MEM"
        case .network: "NET"
        case .disk: "SSD"
        case .cpu: "CPU"
        case .battery: "BAT"
        }
    }

    var symbolName: String {
        switch self {
        case .memory: "memorychip"
        case .network: "globe"
        case .disk: "internaldrive"
        case .cpu: "cpu"
        case .battery: "battery.75percent"
        }
    }

    var shortSymbolName: String {
        switch self {
        case .memory: "memorychip.fill"
        case .network: "globe"
        case .disk: "internaldrive.fill"
        case .cpu: "cpu.fill"
        case .battery: "battery.75percent"
        }
    }

    var tint: Color {
        switch self {
        case .memory: Color(red: 0.22, green: 0.55, blue: 1.0)
        case .network: Color(red: 0.18, green: 0.72, blue: 0.50)
        case .disk: Color(red: 0.98, green: 0.62, blue: 0.22)
        case .cpu: Color(red: 0.82, green: 0.42, blue: 0.92)
        case .battery: Color(red: 0.44, green: 0.74, blue: 0.20)
        }
    }
}

struct MetricReading: Identifiable, Equatable {
    let kind: MetricKind
    let value: Double
    let primaryText: String
    let secondaryText: String
    let detailText: String
    let uploadBytesPerSecond: Double?
    let downloadBytesPerSecond: Double?

    var id: String { kind.rawValue }

    init(
        kind: MetricKind,
        value: Double,
        primaryText: String,
        secondaryText: String,
        detailText: String,
        uploadBytesPerSecond: Double? = nil,
        downloadBytesPerSecond: Double? = nil
    ) {
        self.kind = kind
        self.value = value
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.detailText = detailText
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }
}

struct SystemSnapshot: Equatable {
    var readings: [MetricKind: MetricReading]
    var capturedAt: Date

    static let empty = SystemSnapshot(readings: [:], capturedAt: Date())

    subscript(kind: MetricKind) -> MetricReading? {
        readings[kind]
    }
}

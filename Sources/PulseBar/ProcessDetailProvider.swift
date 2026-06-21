import Foundation

final class ProcessDetailProvider {
    private var previousNetworkRows: [String: (received: Double, sent: Double, date: Date)] = [:]

    func snapshot(for kind: MetricKind, reading: MetricReading?) -> MetricDetailSnapshot {
        switch kind {
        case .memory:
            return memorySnapshot(reading: reading)
        case .network:
            return networkSnapshot(reading: reading)
        case .disk:
            return diskSnapshot(reading: reading)
        case .cpu:
            return cpuSnapshot(reading: reading)
        case .battery:
            return batterySnapshot(reading: reading)
        }
    }

    private func memorySnapshot(reading: MetricReading?) -> MetricDetailSnapshot {
        let rows = processRows()
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(10)
            .map { process in
                MetricDetailRow(
                    id: "memory-\(process.pid)",
                    name: process.name,
                    subtitle: "PID \(process.pid)",
                    primaryValue: MetricFormatter.bytes(Double(process.memoryBytes)),
                    secondaryValue: String(format: "%.1f%% CPU", process.cpuPercent),
                    numericValue: Double(process.memoryBytes)
                )
            }

        return MetricDetailSnapshot(
            kind: .memory,
            summary: reading?.secondaryText ?? "内存排行",
            rows: Array(rows),
            capturedAt: Date(),
            note: "按当前驻留内存排序"
        )
    }

    private func cpuSnapshot(reading: MetricReading?) -> MetricDetailSnapshot {
        let rows = processRows()
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(10)
            .map { process in
                MetricDetailRow(
                    id: "cpu-\(process.pid)",
                    name: process.name,
                    subtitle: "PID \(process.pid)",
                    primaryValue: String(format: "%.1f%%", process.cpuPercent),
                    secondaryValue: MetricFormatter.bytes(Double(process.memoryBytes)),
                    numericValue: process.cpuPercent
                )
            }

        return MetricDetailSnapshot(
            kind: .cpu,
            summary: reading?.secondaryText ?? "CPU 排行",
            rows: Array(rows),
            capturedAt: Date(),
            note: "按当前 CPU 占用排序"
        )
    }

    private func batterySnapshot(reading: MetricReading?) -> MetricDetailSnapshot {
        let rows = processRows()
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(8)
            .map { process in
                MetricDetailRow(
                    id: "battery-\(process.pid)",
                    name: process.name,
                    subtitle: "PID \(process.pid)",
                    primaryValue: String(format: "%.1f%% CPU", process.cpuPercent),
                    secondaryValue: MetricFormatter.bytes(Double(process.memoryBytes)),
                    numericValue: process.cpuPercent
                )
            }

        return MetricDetailSnapshot(
            kind: .battery,
            summary: reading?.secondaryText ?? "电池状态",
            rows: Array(rows),
            capturedAt: Date(),
            note: "macOS 不直接公开 Activity Monitor 的能耗分值，这里用高 CPU 进程作为耗电线索"
        )
    }

    private func networkSnapshot(reading: MetricReading?) -> MetricDetailSnapshot {
        let now = Date()
        let current = nettopRows()
        var rows: [MetricDetailRow] = []

        for item in current {
            let key = "\(item.name)-\(item.pid)"
            let previous = previousNetworkRows[key]
            let interval = max(now.timeIntervalSince(previous?.date ?? now), 0.5)
            let down = max(item.received - (previous?.received ?? item.received), 0) / interval
            let up = max(item.sent - (previous?.sent ?? item.sent), 0) / interval
            let total = down + up
            let fallbackTotal = item.received + item.sent

            rows.append(
                MetricDetailRow(
                    id: "network-\(key)",
                    name: item.name,
                    subtitle: item.pid > 0 ? "PID \(item.pid)" : "进程",
                    primaryValue: total > 0 ? "\(MetricFormatter.speed(total))/s" : MetricFormatter.bytes(fallbackTotal),
                    secondaryValue: "↓ \(MetricFormatter.speed(down))/s  ↑ \(MetricFormatter.speed(up))/s",
                    numericValue: total > 0 ? total : fallbackTotal
                )
            )
        }

        previousNetworkRows = Dictionary(
            uniqueKeysWithValues: current.map {
                ("\($0.name)-\($0.pid)", ($0.received, $0.sent, now))
            }
        )

        let sortedRows = rows
            .sorted { $0.numericValue > $1.numericValue }
            .prefix(10)

        return MetricDetailSnapshot(
            kind: .network,
            summary: reading?.secondaryText ?? "网速排行",
            rows: Array(sortedRows),
            capturedAt: now,
            note: "首次打开时可能先显示累计流量，下一次刷新后显示实时速率"
        )
    }

    private func diskSnapshot(reading: MetricReading?) -> MetricDetailSnapshot {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Pictures")
        ]

        let rows = candidates.compactMap { url -> MetricDetailRow? in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = folderSize(url)
            return MetricDetailRow(
                id: "disk-\(url.path)",
                name: localizedFolderName(url),
                subtitle: url.path,
                primaryValue: MetricFormatter.bytes(Double(bytes)),
                secondaryValue: "常用目录",
                numericValue: Double(bytes)
            )
        }
        .sorted { $0.numericValue > $1.numericValue }

        return MetricDetailSnapshot(
            kind: .disk,
            summary: reading?.secondaryText ?? "硬盘占用",
            rows: rows,
            capturedAt: Date(),
            note: "硬盘详情先展示常用目录占用，避免用高权限文件监听伪装实时进程读写"
        )
    }

    private struct ProcessRow {
        let pid: Int
        let name: String
        let cpuPercent: Double
        let memoryBytes: UInt64
    }

    private struct NetworkRow {
        let pid: Int
        let name: String
        let received: Double
        let sent: Double
    }

    private func processRows() -> [ProcessRow] {
        let output = runCommand("/bin/ps", arguments: ["-axo", "pid=,pcpu=,rss=,comm="])
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = UInt64(parts[2])
            else {
                return nil
            }

            let command = String(parts[3])
            return ProcessRow(
                pid: pid,
                name: URL(fileURLWithPath: command).lastPathComponent,
                cpuPercent: cpu,
                memoryBytes: rssKB * 1024
            )
        }
    }

    private func nettopRows() -> [NetworkRow] {
        let output = runCommand("/usr/bin/nettop", arguments: ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"])
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, fields[0] != "" else { return nil }

            let process = fields[0]
            let processParts = process.split(separator: ".")
            let pid = processParts.last.flatMap { Int($0) } ?? 0
            let name: String
            if processParts.count > 1 {
                name = processParts.dropLast().joined(separator: ".")
            } else {
                name = process
            }

            return NetworkRow(
                pid: pid,
                name: name,
                received: Double(fields[1]) ?? 0,
                sent: Double(fields[2]) ?? 0
            )
        }
        .filter { $0.received + $0.sent > 0 }
    }

    private func folderSize(_ url: URL) -> UInt64 {
        let output = runCommand("/usr/bin/du", arguments: ["-sk", url.path])
        guard let first = output.split(separator: "\t").first ?? output.split(separator: " ").first,
              let kilobytes = UInt64(first)
        else {
            return 0
        }
        return kilobytes * 1024
    }

    private func localizedFolderName(_ url: URL) -> String {
        switch url.lastPathComponent {
        case "Downloads": return "下载"
        case "Desktop": return "桌面"
        case "Documents": return "文稿"
        case "Movies": return "影片"
        case "Pictures": return "图片"
        default: return url.lastPathComponent
        }
    }

    private func runCommand(_ path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

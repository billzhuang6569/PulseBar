import Foundation

final class ProcessDetailProvider {
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
        let rows = current.map { item in
            let key = "\(item.name)-\(item.pid)"
            let down = item.receivedPerSecond
            let up = item.sentPerSecond
            let total = down + up
            let cumulativeTotal = item.totalReceived + item.totalSent

            return MetricDetailRow(
                id: "network-\(key)",
                name: item.name,
                subtitle: item.pid > 0 ? "PID \(item.pid)" : "进程",
                primaryValue: "↓ \(MetricFormatter.speed(down))  ↑ \(MetricFormatter.speed(up))",
                secondaryValue: "累计 \(MetricFormatter.bytes(cumulativeTotal))",
                numericValue: total
            )
        }

        let sortedRows = rows
            .sorted { $0.numericValue > $1.numericValue }
            .prefix(10)

        return MetricDetailSnapshot(
            kind: .network,
            summary: reading?.secondaryText ?? "网速排行",
            rows: Array(sortedRows),
            capturedAt: now,
            note: "按当前上下行合计速度排序；累计流量为进程自启动以来的收发总量"
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
        let receivedPerSecond: Double
        let sentPerSecond: Double
        let totalReceived: Double
        let totalSent: Double
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
        let output = runCommand(
            "/usr/bin/nettop",
            arguments: ["-d", "-P", "-L", "2", "-s", "1", "-x", "-J", "bytes_in,bytes_out"]
        )

        return NettopSampleParser.processTraffic(from: output).map { sample in
            NetworkRow(
                pid: sample.pid,
                name: sample.name,
                receivedPerSecond: sample.receivedPerSecond,
                sentPerSecond: sample.sentPerSecond,
                totalReceived: sample.totalReceived,
                totalSent: sample.totalSent
            )
        }
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

struct NettopProcessTraffic: Equatable {
    let pid: Int
    let name: String
    let receivedPerSecond: Double
    let sentPerSecond: Double
    let totalReceived: Double
    let totalSent: Double
}

enum NettopSampleParser {
    private struct RawRow {
        let pid: Int
        let name: String
        let received: Double
        let sent: Double
    }

    static func processTraffic(from output: String) -> [NettopProcessTraffic] {
        let samples = parseSamples(output)
        guard samples.count >= 2, let totals = samples.first, let deltas = samples.last else {
            return []
        }

        return deltas.values.compactMap { delta in
            let speed = delta.received + delta.sent
            guard speed > 0 else { return nil }

            let key = processKey(name: delta.name, pid: delta.pid)
            let total = totals[key]
            return NettopProcessTraffic(
                pid: delta.pid,
                name: delta.name,
                receivedPerSecond: delta.received,
                sentPerSecond: delta.sent,
                totalReceived: total?.received ?? 0,
                totalSent: total?.sent ?? 0
            )
        }
    }

    private static func parseSamples(_ output: String) -> [[String: RawRow]] {
        var samples: [[String: RawRow]] = []
        var current: [String: RawRow] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }

            if fields[0].isEmpty {
                if !current.isEmpty {
                    samples.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            guard let row = parseRow(fields) else { continue }
            current[processKey(name: row.name, pid: row.pid)] = row
        }

        if !current.isEmpty {
            samples.append(current)
        }
        return samples
    }

    private static func parseRow(_ fields: [String]) -> RawRow? {
        let process = fields[0]
        let processParts = process.split(separator: ".")
        let pid = processParts.last.flatMap { Int($0) } ?? 0
        let name = processParts.count > 1
            ? processParts.dropLast().joined(separator: ".")
            : process

        guard !name.isEmpty,
              let received = Double(fields[1]),
              let sent = Double(fields[2])
        else {
            return nil
        }

        return RawRow(pid: pid, name: name, received: received, sent: sent)
    }

    private static func processKey(name: String, pid: Int) -> String {
        "\(name)-\(pid)"
    }
}

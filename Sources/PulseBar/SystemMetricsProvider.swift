import Darwin
import Foundation
import IOKit.ps

final class SystemMetricsProvider {
    private var previousNetworkTotals: (received: UInt64, sent: UInt64, date: Date)?
    private var previousCPUTicks: (used: UInt64, total: UInt64)?

    func snapshot() -> SystemSnapshot {
        var readings: [MetricKind: MetricReading] = [:]
        readings[.memory] = memoryReading()
        readings[.network] = networkReading()
        readings[.disk] = diskReading()
        readings[.cpu] = cpuReading()
        readings[.battery] = batteryReading()

        return SystemSnapshot(readings: readings, capturedAt: Date())
    }

    private func memoryReading() -> MetricReading {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MetricReading(
                kind: .memory,
                value: 0,
                primaryText: "--",
                secondaryText: "读取失败",
                detailText: "macOS 暂时没有返回内存统计"
            )
        }

        let pageBytes = Double(pageSize)
        let active = Double(stats.active_count) * pageBytes
        let wired = Double(stats.wire_count) * pageBytes
        let compressed = Double(stats.compressor_page_count) * pageBytes
        let free = Double(stats.free_count) * pageBytes
        let used = min(totalBytes, active + wired + compressed)
        let percent = totalBytes > 0 ? used / totalBytes * 100 : 0

        return MetricReading(
            kind: .memory,
            value: percent,
            primaryText: MetricFormatter.percent(percent),
            secondaryText: "\(MetricFormatter.bytes(used)) / \(MetricFormatter.bytes(totalBytes))",
            detailText: "可用 \(MetricFormatter.bytes(free))，已压缩 \(MetricFormatter.bytes(compressed))"
        )
    }

    private func networkReading() -> MetricReading {
        let totals = networkTotals()
        let now = Date()
        defer { previousNetworkTotals = (totals.received, totals.sent, now) }

        guard let previous = previousNetworkTotals else {
            return MetricReading(
                kind: .network,
                value: 0,
                primaryText: "0KB/s",
                secondaryText: "↓ 0KB/s  ↑ 0KB/s",
                detailText: "正在建立网速基线",
                uploadBytesPerSecond: 0,
                downloadBytesPerSecond: 0
            )
        }

        let interval = max(now.timeIntervalSince(previous.date), 0.5)
        let down = Double(totals.received >= previous.received ? totals.received - previous.received : 0) / interval
        let up = Double(totals.sent >= previous.sent ? totals.sent - previous.sent : 0) / interval
        let combined = down + up

        return MetricReading(
            kind: .network,
            value: min(combined / 1_000_000 * 100, 100),
            primaryText: "\(MetricFormatter.compactSpeed(combined))/s",
            secondaryText: "↓ \(MetricFormatter.speed(down))  ↑ \(MetricFormatter.speed(up))",
            detailText: "累计下载 \(MetricFormatter.bytes(Double(totals.received)))，上传 \(MetricFormatter.bytes(Double(totals.sent)))",
            uploadBytesPerSecond: up,
            downloadBytesPerSecond: down
        )
    }

    private func networkTotals() -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var addresses: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return (0, 0)
        }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while pointer != nil {
            guard let interface = pointer?.pointee else {
                pointer = pointer?.pointee.ifa_next
                continue
            }

            let name = String(cString: interface.ifa_name)
            let isLoopback = name.hasPrefix("lo")
            let isLinkLayer = interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)

            if !isLoopback, isLinkLayer, let data = interface.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(networkData.ifi_ibytes)
                sent += UInt64(networkData.ifi_obytes)
            }

            pointer = interface.ifa_next
        }

        return (received, sent)
    }

    private func diskReading() -> MetricReading {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attributes[.systemSize] as? NSNumber)?.doubleValue ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            let used = max(total - free, 0)
            let percent = total > 0 ? used / total * 100 : 0

            return MetricReading(
                kind: .disk,
                value: percent,
                primaryText: MetricFormatter.percent(percent),
                secondaryText: "\(MetricFormatter.bytes(used)) / \(MetricFormatter.bytes(total))",
                detailText: "剩余 \(MetricFormatter.bytes(free))"
            )
        } catch {
            return MetricReading(
                kind: .disk,
                value: 0,
                primaryText: "--",
                secondaryText: "读取失败",
                detailText: error.localizedDescription
            )
        }
    }

    private func cpuReading() -> MetricReading {
        var cpuInfo: processor_info_array_t?
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return MetricReading(
                kind: .cpu,
                value: 0,
                primaryText: "--",
                secondaryText: "读取失败",
                detailText: "macOS 暂时没有返回 CPU 统计"
            )
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var usedTicks: UInt64 = 0
        var totalTicks: UInt64 = 0

        for index in 0..<Int(cpuCount) {
            let base = index * stride
            let user = UInt64(cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(cpuInfo[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            usedTicks += user + system + nice
            totalTicks += user + system + nice + idle
        }

        let percent: Double
        if let previous = previousCPUTicks {
            let usedDelta = usedTicks >= previous.used ? usedTicks - previous.used : 0
            let totalDelta = totalTicks >= previous.total ? totalTicks - previous.total : 0
            percent = totalDelta > 0 ? Double(usedDelta) / Double(totalDelta) * 100 : 0
        } else {
            percent = totalTicks > 0 ? Double(usedTicks) / Double(totalTicks) * 100 : 0
        }
        previousCPUTicks = (usedTicks, totalTicks)

        let coreText = "\(Int(cpuCount)) 核心"
        return MetricReading(
            kind: .cpu,
            value: percent,
            primaryText: MetricFormatter.percent(percent),
            secondaryText: coreText,
            detailText: "系统实时负载"
        )
    }

    private func batteryReading() -> MetricReading {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let source = list.first,
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return MetricReading(
                kind: .battery,
                value: 100,
                primaryText: "AC",
                secondaryText: "外接电源",
                detailText: "没有检测到内置电池"
            )
        }

        let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
        let max = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
        let percent = max > 0 ? current / max * 100 : 0
        let charging = (description[kIOPSIsChargingKey] as? Bool) == true

        return MetricReading(
            kind: .battery,
            value: percent,
            primaryText: MetricFormatter.percent(percent),
            secondaryText: charging ? "正在充电" : "电池供电",
            detailText: description[kIOPSTimeToEmptyKey] as? String ?? "电源状态正常"
        )
    }
}

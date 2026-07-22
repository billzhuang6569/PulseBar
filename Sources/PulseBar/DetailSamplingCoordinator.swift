import Combine
import Foundation

protocol ProcessDetailProviding: AnyObject, Sendable {
    func snapshot(for kind: MetricKind, reading: MetricReading?) -> MetricDetailSnapshot
    func cancel()
}

extension ProcessDetailProvider: ProcessDetailProviding {}

final class DiskDetailCache {
    struct Entry {
        let rows: [MetricDetailRow]
        let capturedAt: Date
    }

    private let lock = NSLock()
    private let ttl: TimeInterval
    private let now: () -> Date
    private var entry: Entry?

    init(ttl: TimeInterval = 15 * 60, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    func value() -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry, now().timeIntervalSince(entry.capturedAt) < ttl else {
            self.entry = nil
            return nil
        }
        return entry
    }

    func store(rows: [MetricDetailRow], capturedAt: Date) {
        lock.lock()
        entry = Entry(rows: rows, capturedAt: capturedAt)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entry = nil
        lock.unlock()
    }
}

@MainActor
final class DetailSamplingCoordinator: ObservableObject {
    @Published private(set) var snapshot: MetricDetailSnapshot?
    @Published private(set) var isRefreshing = false

    private weak var sampler: MetricsSampler?
    private let diskCache: DiskDetailCache
    private let providerFactory: (DiskDetailCache) -> any ProcessDetailProviding
    private var provider: (any ProcessDetailProviding)?
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var kind: MetricKind?
    private var generation = 0

    init(
        diskCache: DiskDetailCache = DiskDetailCache(),
        providerFactory: @escaping (DiskDetailCache) -> any ProcessDetailProviding = {
            ProcessDetailProvider(runner: ProcessCommandRunner(), diskCache: $0)
        }
    ) {
        self.diskCache = diskCache
        self.providerFactory = providerFactory
    }

    func start(kind: MetricKind, sampler: MetricsSampler) {
        stop(clearSnapshot: true)
        generation += 1
        self.kind = kind
        self.sampler = sampler
        provider = providerFactory(diskCache)
        refresh(forceDiskScan: false)
        scheduleTimer(for: kind)
    }

    func refresh(forceDiskScan: Bool = false) {
        guard let kind, let provider, !isRefreshing else { return }
        if forceDiskScan, kind == .disk {
            diskCache.removeAll()
        }

        isRefreshing = true
        let reading = sampler?.snapshot[kind]
        let generation = generation
        refreshTask = Task.detached(priority: .utility) {
            let result = provider.snapshot(for: kind, reading: reading)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.isRefreshing = false
                self.snapshot = result
            }
        }
    }

    func stop(clearSnapshot: Bool = true) {
        generation += 1
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        provider?.cancel()
        provider = nil
        sampler = nil
        kind = nil
        isRefreshing = false
        if clearSnapshot {
            snapshot = nil
        }
    }

    private func scheduleTimer(for kind: MetricKind) {
        guard let interval = kind.detailRefreshInterval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = min(interval * 0.2, 1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension MetricKind {
    var detailRefreshInterval: TimeInterval? {
        switch self {
        case .network:
            return 4
        case .memory, .cpu:
            return 5
        case .battery:
            return 30
        case .disk:
            return nil
        }
    }
}

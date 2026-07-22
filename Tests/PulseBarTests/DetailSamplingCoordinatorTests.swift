import Foundation
import Testing
@testable import PulseBar

@MainActor
struct DetailSamplingCoordinatorTests {
    @Test
    func stopCancelsProviderAndRejectsLateSnapshot() async {
        let provider = SlowDetailProvider()
        let coordinator = DetailSamplingCoordinator(providerFactory: { _ in provider })
        let sampler = MetricsSampler(provider: EmptyMetricsProvider())

        coordinator.start(kind: .memory, sampler: sampler)
        coordinator.stop()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(provider.wasCancelled)
        #expect(coordinator.snapshot == nil)
        #expect(!coordinator.isRefreshing)
    }

    @Test
    func diskCacheExpiresAfterItsTimeToLive() {
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = DiskDetailCache(ttl: 900, now: { now })
        cache.store(rows: [], capturedAt: now)

        #expect(cache.value() != nil)
        now = now.addingTimeInterval(901)
        #expect(cache.value() == nil)
    }
}

private final class SlowDetailProvider: ProcessDetailProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func snapshot(for kind: MetricKind, reading: MetricReading?) -> MetricDetailSnapshot {
        Thread.sleep(forTimeInterval: 0.2)
        return MetricDetailSnapshot(kind: kind, summary: "late", rows: [], capturedAt: Date(), note: nil)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class EmptyMetricsProvider: SystemMetricsProviding {
    func snapshot(kinds: Set<MetricKind>) -> SystemSnapshot {
        SystemSnapshot(readings: [:], capturedAt: Date())
    }

    func resetBaselines(for kinds: Set<MetricKind>) {}
}

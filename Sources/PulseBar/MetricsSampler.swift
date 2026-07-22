import Combine
import Foundation

protocol SystemMetricsProviding: AnyObject {
    func snapshot(kinds: Set<MetricKind>) -> SystemSnapshot
    func resetBaselines(for kinds: Set<MetricKind>)
}

extension SystemMetricsProvider: SystemMetricsProviding {}

@MainActor
final class MetricsSampler: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot = .empty

    private let provider: SystemMetricsProviding
    private var configuration = SamplingConfiguration(
        mode: .menuBarOnly,
        menuBarKind: .memory,
        enabledKinds: Set(MetricKind.allCases),
        refreshInterval: 2
    )
    private var lastSampledAt: [MetricKind: Date] = [:]
    private var timer: Timer?
    private var powerStateCancellable: AnyCancellable?
    private var isRunning = false

    init(provider: SystemMetricsProviding = SystemMetricsProvider()) {
        self.provider = provider
        powerStateCancellable = NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleNextTick()
            }
    }

    func configure(_ configuration: SamplingConfiguration) {
        guard self.configuration != configuration else { return }
        let previousKinds = self.configuration.requiredKinds
        self.configuration = configuration
        let newKinds = configuration.requiredKinds
        let activatedKinds = newKinds.subtracting(previousKinds)
        provider.resetBaselines(for: activatedKinds)
        lastSampledAt = lastSampledAt.filter { newKinds.contains($0.key) }

        guard isRunning else { return }
        if activatedKinds.isEmpty {
            scheduleNextTick()
        } else {
            refresh(kinds: activatedKinds)
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        provider.resetBaselines(for: configuration.requiredKinds)
        refresh(kinds: configuration.requiredKinds)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        refresh(kinds: configuration.requiredKinds)
    }

    private func refresh(kinds: Set<MetricKind>) {
        guard isRunning, !kinds.isEmpty else { return }
        timer?.invalidate()
        timer = nil

        let partial = provider.snapshot(kinds: kinds)
        var readings = snapshot.readings
        for (kind, reading) in partial.readings {
            readings[kind] = reading
            lastSampledAt[kind] = partial.capturedAt
        }

        if readings != snapshot.readings {
            snapshot = SystemSnapshot(readings: readings, capturedAt: partial.capturedAt)
        }
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil

        let now = Date()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let nextDelay = configuration.requiredKinds.map { kind -> TimeInterval in
            guard let lastSampled = lastSampledAt[kind] else { return 0 }
            let interval = configuration.interval(for: kind, lowPowerMode: lowPowerMode)
            return max(interval - now.timeIntervalSince(lastSampled), 0)
        }.min() ?? 60

        let delay = max(nextDelay, 0.1)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDueKinds()
            }
        }
        timer.tolerance = min(delay * 0.2, 1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refreshDueKinds() {
        let now = Date()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let dueKinds = configuration.requiredKinds.filter { kind in
            guard let lastSampled = lastSampledAt[kind] else { return true }
            let interval = configuration.interval(for: kind, lowPowerMode: lowPowerMode)
            return now.timeIntervalSince(lastSampled) >= interval - 0.05
        }

        if dueKinds.isEmpty {
            scheduleNextTick()
        } else {
            refresh(kinds: dueKinds)
        }
    }
}

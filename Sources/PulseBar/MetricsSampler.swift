import Combine
import Foundation

final class MetricsSampler: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot = .empty

    private let provider = SystemMetricsProvider()
    private var timer: Timer?

    func start(interval: TimeInterval = 2) {
        stop()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        snapshot = provider.snapshot()
    }
}

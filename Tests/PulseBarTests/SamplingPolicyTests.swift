import Foundation
import Testing
@testable import PulseBar

struct SamplingPolicyTests {
    @Test
    func hiddenPanelOnlyRequestsTheMenuBarMetric() {
        let configuration = SamplingConfiguration(
            mode: .menuBarOnly,
            menuBarKind: .network,
            enabledKinds: Set(MetricKind.allCases),
            refreshInterval: 2
        )

        #expect(configuration.requiredKinds == [.network])
    }

    @Test
    func visibleDashboardRequestsOnlyEnabledMetrics() {
        let configuration = SamplingConfiguration(
            mode: .dashboardVisible,
            menuBarKind: .network,
            enabledKinds: [.memory, .network, .cpu],
            refreshInterval: 2
        )

        #expect(configuration.requiredKinds == [.memory, .network, .cpu])
    }

    @Test
    func slowMetricsIgnoreTheFastRefreshSetting() {
        let configuration = SamplingConfiguration(
            mode: .dashboardVisible,
            menuBarKind: .network,
            enabledKinds: Set(MetricKind.allCases),
            refreshInterval: 1
        )

        #expect(configuration.interval(for: .disk, lowPowerMode: false) == 60)
        #expect(configuration.interval(for: .battery, lowPowerMode: false) == 60)
        #expect(configuration.interval(for: .memory, lowPowerMode: false) == 5)
        #expect(configuration.interval(for: .cpu, lowPowerMode: false) == 3)
    }

    @Test
    func lowPowerModeDoublesEveryInterval() {
        let configuration = SamplingConfiguration(
            mode: .menuBarOnly,
            menuBarKind: .network,
            enabledKinds: [.network],
            refreshInterval: 2
        )

        #expect(configuration.interval(for: .network, lowPowerMode: true) == 4)
    }
}

@MainActor
struct MetricsSamplerTests {
    @Test
    func samplerAsksProviderForConfiguredKinds() {
        let provider = MetricsProviderSpy()
        let sampler = MetricsSampler(provider: provider)
        sampler.configure(
            SamplingConfiguration(
                mode: .menuBarOnly,
                menuBarKind: .cpu,
                enabledKinds: Set(MetricKind.allCases),
                refreshInterval: 2
            )
        )

        sampler.start()
        sampler.stop()

        #expect(provider.requestedKinds == [[.cpu]])
    }
}

private final class MetricsProviderSpy: SystemMetricsProviding {
    var requestedKinds: [Set<MetricKind>] = []

    func snapshot(kinds: Set<MetricKind>) -> SystemSnapshot {
        requestedKinds.append(kinds)
        return SystemSnapshot(readings: [:], capturedAt: Date())
    }

    func resetBaselines(for kinds: Set<MetricKind>) {}
}

import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let preferences: DisplayPreferences
    private let sampler: MetricsSampler
    private var cancellables = Set<AnyCancellable>()

    init(preferences: DisplayPreferences, sampler: MetricsSampler) {
        self.preferences = preferences
        self.sampler = sampler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configurePopover()
        configureButton()
        bindUpdates()
        updateStatusItem(snapshot: sampler.snapshot)
    }

    func stop() {
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 440, height: 610)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(preferences: preferences, sampler: sampler)
        )
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageLeading
        button.toolTip = "PulseBar 系统状态"
    }

    private func bindUpdates() {
        sampler.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateStatusItem(snapshot: snapshot)
            }
            .store(in: &cancellables)

        preferences.$enabledKinds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                updateStatusItem(snapshot: sampler.snapshot)
            }
            .store(in: &cancellables)

        preferences.$showPercentLabels
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                updateStatusItem(snapshot: sampler.snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(snapshot: SystemSnapshot) {
        guard let button = statusItem.button else { return }

        let enabledKinds = MetricKind.allCases.filter { preferences.enabledKinds.contains($0) }
        let primaryKind = enabledKinds.first ?? .memory
        let readings = enabledKinds.compactMap { snapshot[$0] }

        button.image = NSImage(systemSymbolName: primaryKind.symbolName, accessibilityDescription: primaryKind.title)
        button.image?.isTemplate = true
        button.title = statusTitle(for: readings)
        button.contentTintColor = .labelColor
    }

    private func statusTitle(for readings: [MetricReading]) -> String {
        if readings.isEmpty { return " --" }

        let parts = readings.prefix(3).map { reading in
            switch reading.kind {
            case .memory, .disk, .cpu, .battery:
                return preferences.showPercentLabels ? "\(reading.kind.title) \(reading.primaryText)" : reading.primaryText
            case .network:
                return reading.secondaryText
                    .replacingOccurrences(of: "↓ ", with: "↓")
                    .replacingOccurrences(of: "  ↑ ", with: " ↑")
            }
        }

        return " " + parts.joined(separator: "  ")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

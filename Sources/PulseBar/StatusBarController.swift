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
        statusItem = NSStatusBar.system.statusItem(withLength: 62)
        statusItem.autosaveName = "PulseBarStatusItem"

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

        preferences.$menuBarKind
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                updateStatusItem(snapshot: sampler.snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(snapshot: SystemSnapshot) {
        guard let button = statusItem.button else { return }

        let primaryKind = preferences.menuBarKind
        let reading = snapshot[primaryKind]

        statusItem.length = preferences.showPercentLabels ? 62 : 28
        button.image = NSImage(systemSymbolName: primaryKind.shortSymbolName, accessibilityDescription: primaryKind.title)
        button.image?.isTemplate = true
        button.title = preferences.showPercentLabels ? statusTitle(for: reading, kind: primaryKind) : ""
        button.contentTintColor = .labelColor
    }

    private func statusTitle(for reading: MetricReading?, kind: MetricKind) -> String {
        guard let reading else { return " --" }
        switch kind {
        case .network:
            let cleaned = reading.primaryText
                .replacingOccurrences(of: "/s", with: "")
                .replacingOccurrences(of: " ", with: "")
            return " \(cleaned.prefix(5))"
        case .battery where reading.primaryText == "AC":
            return " AC"
        default:
            return " \(MetricFormatter.compactPercent(reading.value))%"
        }
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

import AppKit
import Combine
import SwiftUI

final class PulsePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class StatusBarController: NSObject {
    private enum Layout {
        static let panelSize = NSSize(width: 348, height: 480)
        static let screenMargin: CGFloat = 10
        static let menuBarGap: CGFloat = 22
    }

    private let statusItem: NSStatusItem
    private let panel: NSPanel
    private let preferences: DisplayPreferences
    private let sampler: MetricsSampler
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    init(preferences: DisplayPreferences, sampler: MetricsSampler) {
        self.preferences = preferences
        self.sampler = sampler
        statusItem = NSStatusBar.system.statusItem(withLength: 62)
        statusItem.autosaveName = "PulseBarStatusItem"
        panel = PulsePanel(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        configureButton()
        bindUpdates()
        updateStatusItem(snapshot: sampler.snapshot)

        if ProcessInfo.processInfo.environment["PULSEBAR_SHOW_PANEL_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.showPanelFromStatusItem()
            }
        }
    }

    func stop() {
        cancellables.removeAll()
        removeOutsideClickMonitor()
        panel.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configurePanel() {
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: DashboardView(preferences: preferences, sampler: sampler)
        )
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
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

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if panel.isVisible {
            closePanel()
        } else {
            showPanel(relativeTo: button)
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        positionPanel(relativeTo: button)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard self?.panel.isVisible == true else { return }
            self?.installOutsideClickMonitor()
        }
    }

    private func showPanelFromStatusItem() {
        guard let button = statusItem.button else { return }
        showPanel(relativeTo: button)
    }

    private func closePanel() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        let screen = button.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let panelSize = Layout.panelSize

        let statusFrame = button.window.map { window in
            window.convertToScreen(button.convert(button.bounds, to: nil))
        }

        let anchorMaxX = statusFrame?.maxX ?? visibleFrame.maxX
        let idealX = anchorMaxX - panelSize.width
        let x = min(
            max(idealX, visibleFrame.minX + Layout.screenMargin),
            visibleFrame.maxX - panelSize.width - Layout.screenMargin
        )

        let topBelowMenuBar = (statusFrame?.minY ?? visibleFrame.maxY) - Layout.menuBarGap
        let idealY = topBelowMenuBar - panelSize.height
        let y = min(
            max(idealY, visibleFrame.minY + Layout.screenMargin),
            visibleFrame.maxY - panelSize.height - Layout.menuBarGap
        )

        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePanel()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}

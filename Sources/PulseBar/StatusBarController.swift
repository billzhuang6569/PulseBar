import AppKit
import Combine
import SwiftUI

final class PulsePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class MenuBarMetricView: NSView {
    var onClick: (() -> Void)?

    private var kind: MetricKind = .memory
    private var reading: MetricReading?
    private var showsValue = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func update(kind: MetricKind, reading: MetricReading?, showsValue: Bool, width: CGFloat) {
        self.kind = kind
        self.reading = reading
        self.showsValue = showsValue
        frame = NSRect(x: frame.minX, y: frame.minY, width: width, height: NSStatusBar.system.thickness)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds
        let iconName = kind.shortSymbolName
        let iconSize: CGFloat = kind == .network && showsValue ? 15 : 14
        let iconX: CGFloat = showsValue ? 6 : (bounds.width - iconSize) / 2
        let iconY = (bounds.height - iconSize) / 2

        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: kind.title) {
            icon.isTemplate = true
            NSColor.labelColor.set()
            icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        }

        guard showsValue else { return }

        if kind == .network {
            drawNetworkText(in: bounds)
        } else {
            drawSingleValueText(in: bounds)
        }
    }

    private func drawNetworkText(in bounds: NSRect) {
        let upload = MetricFormatter.compactSpeed(reading?.uploadBytesPerSecond ?? 0)
        let download = MetricFormatter.compactSpeed(reading?.downloadBytesPerSecond ?? 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.4, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        NSAttributedString(string: "↑ \(upload)", attributes: attributes)
            .draw(at: NSPoint(x: 25, y: 17.1))
        NSAttributedString(string: "↓ \(download)", attributes: attributes)
            .draw(at: NSPoint(x: 25, y: 4.1))
    }

    private func drawSingleValueText(in bounds: NSRect) {
        let text: String
        if kind == .battery, reading?.primaryText == "AC" {
            text = "AC"
        } else {
            text = "\(MetricFormatter.compactPercent(reading?.value ?? 0))%"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]

        NSAttributedString(string: text, attributes: attributes)
            .draw(at: NSPoint(x: 25, y: 8.7))
    }
}

final class StatusBarController: NSObject {
    private enum Layout {
        static let panelSize = NSSize(width: 348, height: 480)
        static let screenMargin: CGFloat = 10
        static let menuBarGap: CGFloat = 22
    }

    private let statusItem: NSStatusItem
    private let statusView: MenuBarMetricView
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
        statusView = MenuBarMetricView(frame: NSRect(x: 0, y: 0, width: 62, height: NSStatusBar.system.thickness))
        panel = PulsePanel(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        configureStatusView()
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

    private func configureStatusView() {
        statusView.onClick = { [weak self] in
            self?.togglePanelFromStatusItem()
        }
        statusView.toolTip = "PulseBar 系统状态"
        statusItem.view = statusView
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
        let primaryKind = preferences.menuBarKind
        let reading = snapshot[primaryKind]

        let width = statusItemWidth(kind: primaryKind)
        statusItem.length = width
        statusView.update(kind: primaryKind, reading: reading, showsValue: preferences.showPercentLabels, width: width)
    }

    private func statusItemWidth(kind: MetricKind) -> CGFloat {
        guard preferences.showPercentLabels else { return 28 }
        return kind == .network ? 76 : 62
    }

    private func togglePanelFromStatusItem() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel(relativeTo: statusView)
        }
    }

    private func showPanel(relativeTo anchorView: NSView) {
        positionPanel(relativeTo: anchorView)
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
        showPanel(relativeTo: statusView)
    }

    private func closePanel() {
        removeOutsideClickMonitor()
        panel.orderOut(nil)
    }

    private func positionPanel(relativeTo anchorView: NSView) {
        let screen = anchorView.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let panelSize = Layout.panelSize

        let statusFrame = anchorView.window.map { window in
            window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
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

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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
        let iconSize: CGFloat = kind == .network && showsValue ? 13 : 13
        let iconX: CGFloat = showsValue ? 6 : (bounds.width - iconSize) / 2
        let iconY = (bounds.height - iconSize) / 2
        let foreground = adaptiveMenuBarForeground()

        if let icon = tintedStatusIcon(named: iconName, accessibilityDescription: kind.title, color: foreground) {
            icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        }

        guard showsValue else { return }

        if kind == .network {
            drawNetworkText(in: bounds, foreground: foreground)
        } else {
            drawSingleValueText(in: bounds, foreground: foreground)
        }
    }

    private func adaptiveMenuBarForeground() -> NSColor {
        let appearance = effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight])

        switch match {
        case .darkAqua, .vibrantDark:
            return NSColor.white
        case .aqua, .vibrantLight:
            return NSColor(calibratedWhite: 0.02, alpha: 1)
        default:
            return NSColor.labelColor
        }
    }

    private func tintedStatusIcon(named name: String, accessibilityDescription: String, color: NSColor) -> NSImage? {
        guard let source = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription) else {
            return nil
        }

        let image = NSImage(size: source.size)
        image.lockFocus()
        let sourceRect = NSRect(origin: .zero, size: source.size)
        source.draw(in: sourceRect, from: sourceRect, operation: .sourceOver, fraction: 1)
        color.set()
        sourceRect.fill(using: .sourceIn)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawNetworkText(in bounds: NSRect, foreground: NSColor) {
        let upload = MetricFormatter.compactSpeed(reading?.uploadBytesPerSecond ?? 0)
        let download = MetricFormatter.compactSpeed(reading?.downloadBytesPerSecond ?? 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.6, weight: .semibold),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]

        NSAttributedString(string: "↑ \(upload)", attributes: attributes)
            .draw(at: NSPoint(x: 24, y: 14.4))
        NSAttributedString(string: "↓ \(download)", attributes: attributes)
            .draw(at: NSPoint(x: 24, y: 3.0))
    }

    private func drawSingleValueText(in bounds: NSRect, foreground: NSColor) {
        let text: String
        if kind == .battery, reading?.primaryText == "AC" {
            text = "AC"
        } else {
            text = "\(MetricFormatter.compactPercent(reading?.value ?? 0))%"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: foreground
        ]

        NSAttributedString(string: text, attributes: attributes)
            .draw(at: NSPoint(x: 24, y: 9.2))
    }
}

@MainActor
final class StatusBarController: NSObject {
    private enum Layout {
        static let panelSize = NSSize(width: 340, height: 560)
        static let detailPanelSize = NSSize(width: 286, height: 360)
        static let panelCornerRadius: CGFloat = 20
        static let detailPanelCornerRadius: CGFloat = 16
        static let screenMargin: CGFloat = 10
        static let menuBarGap: CGFloat = 22
        static let detailGap: CGFloat = 8
    }

    private let statusItem: NSStatusItem
    private let statusView: MenuBarMetricView
    private let panel: NSPanel
    private let detailPanel: NSPanel
    private let preferences: DisplayPreferences
    private let sampler: MetricsSampler
    private let detailCoordinator = DetailSamplingCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?
    private var selectedDetailKind: MetricKind?

    init(preferences: DisplayPreferences, sampler: MetricsSampler) {
        self.preferences = preferences
        self.sampler = sampler
        statusItem = NSStatusBar.system.statusItem(withLength: 62)
        statusItem.autosaveName = "ZhuangSirStatusBarItem"
        statusView = MenuBarMetricView(frame: NSRect(x: 0, y: 0, width: 62, height: NSStatusBar.system.thickness))
        panel = PulsePanel(
            contentRect: NSRect(origin: .zero, size: Layout.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        detailPanel = PulsePanel(
            contentRect: NSRect(origin: .zero, size: Layout.detailPanelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
        configureDetailPanel()
        configureStatusView()
        bindUpdates()
        configureSampling()
        sampler.start()
        updateStatusItem(snapshot: sampler.snapshot)

        if ProcessInfo.processInfo.environment["PULSEBAR_SHOW_PANEL_ON_LAUNCH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                showPanelFromStatusItem()
                showDiagnosticDetailIfRequested()
            }
        }
    }

    func stop() {
        cancellables.removeAll()
        removeOutsideClickMonitor()
        detailCoordinator.stop()
        sampler.stop()
        panel.orderOut(nil)
        detailPanel.orderOut(nil)
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
            rootView: DashboardView(preferences: preferences, sampler: sampler) { [weak self] kind in
                self?.setDetailKind(kind)
            }
        )
        applyRoundedContentMask(to: panel, radius: Layout.panelCornerRadius)
    }

    private func configureDetailPanel() {
        detailPanel.titleVisibility = .hidden
        detailPanel.isMovableByWindowBackground = false
        detailPanel.isReleasedWhenClosed = false
        detailPanel.isFloatingPanel = true
        detailPanel.hidesOnDeactivate = false
        detailPanel.level = .statusBar
        detailPanel.backgroundColor = .clear
        detailPanel.isOpaque = false
        detailPanel.hasShadow = true
        detailPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        detailPanel.standardWindowButton(.closeButton)?.isHidden = true
        detailPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        detailPanel.standardWindowButton(.zoomButton)?.isHidden = true
        applyRoundedContentMask(to: detailPanel, radius: Layout.detailPanelCornerRadius)
    }

    private func applyRoundedContentMask(to panel: NSPanel, radius: CGFloat) {
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.cornerRadius = radius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
    }

    private func configureStatusView() {
        statusView.onClick = { [weak self] in
            self?.togglePanelFromStatusItem()
        }
        statusView.toolTip = "庄Sir的状态栏"
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
                configureSampling()
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
                configureSampling()
                updateStatusItem(snapshot: sampler.snapshot)
            }
            .store(in: &cancellables)

        preferences.$refreshInterval
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.configureSampling()
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
        return kind == .network ? 74 : 58
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
        configureSampling()

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

    private func showDiagnosticDetailIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        if let rawKind = environment["PULSEBAR_SHOW_DETAIL_ON_LAUNCH"],
           let kind = MetricKind(rawValue: rawKind) {
            setDetailKind(kind)
        }

        if let rawDelay = environment["PULSEBAR_CLOSE_PANEL_AFTER_SECONDS"],
           let delay = TimeInterval(rawDelay), delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.closePanel()
            }
        }
    }

    private func closePanel() {
        removeOutsideClickMonitor()
        detailCoordinator.stop()
        panel.orderOut(nil)
        detailPanel.orderOut(nil)
        selectedDetailKind = nil
        configureSampling()
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

    private func setDetailKind(_ kind: MetricKind?) {
        guard panel.isVisible else { return }

        guard let kind else {
            selectedDetailKind = nil
            detailCoordinator.stop()
            detailPanel.orderOut(nil)
            configureSampling()
            return
        }

        selectedDetailKind = kind
        detailCoordinator.start(kind: kind, sampler: sampler)
        configureSampling()
        detailPanel.contentViewController = NSHostingController(
            rootView: MetricDetailPanelView(kind: kind, coordinator: detailCoordinator)
        )
        positionDetailPanel()
        detailPanel.alphaValue = 0
        detailPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            detailPanel.animator().alphaValue = 1
        }
    }

    private func positionDetailPanel() {
        let screen = panel.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let detailSize = Layout.detailPanelSize
        let panelFrame = panel.frame

        let rightX = panelFrame.maxX + Layout.detailGap
        let leftX = panelFrame.minX - detailSize.width - Layout.detailGap
        let hasRightSpace = rightX + detailSize.width + Layout.screenMargin <= visibleFrame.maxX
        let idealX = hasRightSpace ? rightX : leftX
        let x = min(
            max(idealX, visibleFrame.minX + Layout.screenMargin),
            visibleFrame.maxX - detailSize.width - Layout.screenMargin
        )

        let idealY = panelFrame.maxY - detailSize.height
        let y = min(
            max(idealY, visibleFrame.minY + Layout.screenMargin),
            visibleFrame.maxY - detailSize.height - Layout.menuBarGap
        )

        detailPanel.setFrame(NSRect(x: x, y: y, width: detailSize.width, height: detailSize.height), display: true)
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

    private func configureSampling() {
        let mode: SamplingMode
        if panel.isVisible, let selectedDetailKind {
            mode = .detailVisible(selectedDetailKind)
        } else if panel.isVisible {
            mode = .dashboardVisible
        } else {
            mode = .menuBarOnly
        }

        sampler.configure(
            SamplingConfiguration(
                mode: mode,
                menuBarKind: preferences.menuBarKind,
                enabledKinds: preferences.enabledKinds,
                refreshInterval: preferences.refreshInterval
            )
        )
    }
}

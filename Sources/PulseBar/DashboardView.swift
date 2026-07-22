import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var sampler: MetricsSampler
    var onSelectDetail: (MetricKind?) -> Void = { _ in }
    @State private var selectedDetailKind: MetricKind?
    @State private var carouselIndex = 0

    private var visibleReadings: [MetricReading] {
        MetricKind.allCases.compactMap { kind in
            guard preferences.enabledKinds.contains(kind) else { return nil }
            return sampler.snapshot[kind]
        }
    }

    private var pressureValue: Double {
        let memory = sampler.snapshot[.memory]?.value ?? 0
        let cpu = sampler.snapshot[.cpu]?.value ?? 0
        let disk = sampler.snapshot[.disk]?.value ?? 0
        return min(max((memory * 0.45) + (cpu * 0.35) + (disk * 0.20), 0), 100)
    }

    private var pressureText: String {
        switch pressureValue {
        case 0..<45: "状态轻盈"
        case 45..<72: "负载适中"
        case 72..<88: "需要留意"
        default: "压力偏高"
        }
    }

    private var pressureColor: Color {
        switch pressureValue {
        case 0..<45: DashboardTheme.accent
        case 45..<72: Color(red: 0.34, green: 0.64, blue: 1.0)
        case 72..<88: Color(red: 0.96, green: 0.58, blue: 0.18)
        default: Color(red: 0.95, green: 0.22, blue: 0.28)
        }
    }

    var body: some View {
        ZStack {
            DashboardTheme.backgroundGradient

            VStack(spacing: 8) {
                header
                pressurePanel
                signalStrip
                metricCarousel

                settingsPanel
                footer
            }
            .padding(12)
        }
        .frame(width: DashboardLayout.width, height: DashboardLayout.height)
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius, style: .continuous)
                .stroke(DashboardTheme.windowStroke, lineWidth: 1)
        }
    }

    private var metricCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(visibleReadings.enumerated()), id: \.element.id) { index, reading in
                        MetricTile(reading: reading, isSelected: selectedDetailKind == reading.kind) {
                            let nextSelection = selectedDetailKind == reading.kind ? nil : reading.kind
                            selectedDetailKind = nextSelection
                            onSelectDetail(nextSelection)
                            carouselIndex = index
                        }
                        .id(reading.kind.id)
                    }
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 1)
            }
            .frame(height: 174)
            .overlay(alignment: .leading) {
                if carouselIndex > 0 {
                    CarouselArrow(systemName: "chevron.left") {
                        moveCarousel(by: -1, proxy: proxy)
                    }
                    .padding(.leading, 2)
                }
            }
            .overlay(alignment: .trailing) {
                if carouselIndex < max(visibleReadings.count - 1, 0) {
                    CarouselArrow(systemName: "chevron.right") {
                        moveCarousel(by: 1, proxy: proxy)
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .onChange(of: preferences.enabledKinds) { _, _ in
            if let selectedDetailKind, !preferences.isEnabled(selectedDetailKind) {
                self.selectedDetailKind = nil
                onSelectDetail(nil)
            }
            carouselIndex = min(carouselIndex, max(visibleReadings.count - 1, 0))
        }
    }

    private func moveCarousel(by delta: Int, proxy: ScrollViewProxy) {
        guard !visibleReadings.isEmpty else { return }
        let nextIndex = min(max(carouselIndex + delta, 0), visibleReadings.count - 1)
        carouselIndex = nextIndex
        withAnimation(.snappy(duration: 0.22)) {
            proxy.scrollTo(visibleReadings[nextIndex].kind.id, anchor: .center)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.56, blue: 0.72),
                                Color(red: 0.64, green: 0.95, blue: 0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("庄Sir的状态栏")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                Text("实时 Mac 状态")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DashboardTheme.secondaryText)
            }

            Spacer()

            Text(sampler.snapshot.capturedAt, style: .time)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTheme.primaryText.opacity(0.82))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DashboardTheme.pillBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var pressurePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pressureText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)
                    Text("综合内存、CPU 与硬盘压力")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardTheme.secondaryText)
                }

                Spacer()

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(pressureValue.rounded()))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("分")
                        .font(.system(size: 11, weight: .semibold))
                }
                .monospacedDigit()
                .foregroundStyle(pressureColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardTheme.track)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [pressureColor.opacity(0.62), pressureColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, proxy.size.width * pressureValue / 100))
                }
            }
            .frame(height: 6)
        }
        .padding(11)
        .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DashboardTheme.stroke, lineWidth: 1)
        }
    }

    private var signalStrip: some View {
        HStack(spacing: 6) {
            ForEach(MetricKind.allCases) { kind in
                if let reading = sampler.snapshot[kind] {
                    MetricFocusCard(reading: reading, preferences: preferences)
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("显示设置", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.primaryText)

                Spacer()

                Toggle("显示数值", isOn: $preferences.showPercentLabels)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .tint(DashboardTheme.accent)
            }

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DashboardTheme.secondaryText)
                Slider(value: $preferences.refreshInterval, in: 1...5, step: 1)
                    .tint(DashboardTheme.accent)
                Text("\(Int(preferences.refreshInterval))s")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(11)
        .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DashboardTheme.stroke, lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                sampler.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(PanelButtonStyle())

            Spacer()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .buttonStyle(PanelButtonStyle())
        }
        .controlSize(.small)
    }
}

private struct MetricFocusCard: View {
    let reading: MetricReading
    @ObservedObject var preferences: DisplayPreferences

    private var isEnabled: Bool {
        preferences.isEnabled(reading.kind)
    }

    private var isFocused: Bool {
        preferences.menuBarKind == reading.kind && isEnabled
    }

    private var foreground: Color {
        if !isEnabled { return DashboardTheme.disabledText }
        return isFocused ? reading.kind.tint : DashboardTheme.primaryText
    }

    private var valueText: String {
        isEnabled ? reading.primaryText : "关闭"
    }

    var body: some View {
        VStack(spacing: 5) {
            Button {
                guard isEnabled else { return }
                preferences.menuBarKind = reading.kind
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: reading.kind.shortSymbolName)
                        .font(.system(size: 12, weight: .bold))
                    Text(valueText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 37)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(foreground)

            MiniSwitch(isOn: isEnabled, tint: reading.kind.tint) {
                preferences.set(reading.kind, enabled: !isEnabled)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 61)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused ? 1.2 : 1)
        }
        .opacity(isEnabled ? 1 : 0.62)
    }

    private var background: Color {
        if !isEnabled { return DashboardTheme.disabledSurface }
        if isFocused { return reading.kind.tint.opacity(0.18) }
        return DashboardTheme.surfaceRaised
    }

    private var borderColor: Color {
        if !isEnabled { return DashboardTheme.stroke.opacity(0.55) }
        if isFocused { return reading.kind.tint.opacity(0.82) }
        return DashboardTheme.stroke
    }
}

private struct MiniSwitch: View {
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? tint.opacity(0.9) : DashboardTheme.switchOff)
                .frame(width: 26, height: 14)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Color.white : DashboardTheme.disabledText)
                        .frame(width: 10, height: 10)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct MetricTile: View {
    let reading: MetricReading
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: reading.kind.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(reading.kind.tint)
                        .frame(width: 17)

                    Text(reading.kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DashboardTheme.primaryText)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? reading.kind.tint : DashboardTheme.tertiaryText)
                }

                Text(reading.primaryText)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                ProgressView(value: reading.value, total: 100)
                    .tint(reading.kind.tint)
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 3) {
                    Text(reading.secondaryText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(reading.detailText)
                        .font(.system(size: 10))
                        .foregroundStyle(DashboardTheme.tertiaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(width: 156, height: 150, alignment: .top)
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(DashboardTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? reading.kind.tint.opacity(0.9) : DashboardTheme.stroke, lineWidth: isSelected ? 1.4 : 1)
        }
    }
}

private struct CarouselArrow: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DashboardTheme.primaryText)
                .frame(width: 30, height: 46)
                .background(.black.opacity(0.42), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(DashboardTheme.stroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
    }
}

struct MetricDetailPanelView: View {
    let kind: MetricKind
    @ObservedObject var coordinator: DetailSamplingCoordinator

    var body: some View {
        ZStack {
            DashboardTheme.backgroundGradient

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(kind.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(kind.title)详情")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                        Text(coordinator.snapshot?.summary ?? "正在读取")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        coordinator.refresh(forceDiskScan: kind == .disk)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .disabled(coordinator.isRefreshing)
                    .opacity(coordinator.isRefreshing ? 0.45 : 1)
                    .help(kind == .disk ? "重新扫描常用目录" : "立即刷新")

                    Text(coordinator.snapshot?.capturedAt ?? Date(), style: .time)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DashboardTheme.tertiaryText)
                }

                ScrollView(showsIndicators: false) {
                    if let snapshot = coordinator.snapshot {
                        DetailRows(snapshot: snapshot)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DashboardTheme.surfaceRaised)
                                    .frame(height: 34)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: 286, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DashboardTheme.windowStroke, lineWidth: 1)
        }
    }
}

private struct DetailRows: View {
    let snapshot: MetricDetailSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.rows.isEmpty {
                Text(snapshot.kind == .network ? "当前采样周期没有进程使用网络" : "暂时没有可展示的明细")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(DashboardTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(snapshot.rows) { row in
                    if snapshot.kind == .network {
                        NetworkDetailRowView(row: row, tint: snapshot.kind.tint)
                    } else {
                        DetailRowView(row: row, tint: snapshot.kind.tint)
                    }
                }
            }

            if let note = snapshot.note {
                Text(note)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DashboardTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }
}

private struct NetworkDetailRowView: View {
    let row: MetricDetailRow
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text(row.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(row.primaryValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(spacing: 8) {
                Text(row.secondaryValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(row.subtitle)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DashboardTheme.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.leading, 15)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(DashboardTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DashboardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct DetailRowView: View {
    let row: MetricDetailRow
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DashboardTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.primaryValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DashboardTheme.primaryText)
                Text(row.secondaryValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(DashboardTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DashboardTheme.stroke, lineWidth: 1)
        }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DashboardTheme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DashboardTheme.pillBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(DashboardTheme.stroke, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

private enum DashboardLayout {
    static let width: CGFloat = 340
    static let height: CGFloat = 560
    static let panelCornerRadius: CGFloat = 20
}

private enum DashboardTheme {
    static let primaryText = Color(red: 0.94, green: 0.97, blue: 0.94)
    static let secondaryText = Color(red: 0.62, green: 0.68, blue: 0.64)
    static let tertiaryText = Color(red: 0.42, green: 0.48, blue: 0.45)
    static let disabledText = Color(red: 0.44, green: 0.49, blue: 0.47)
    static let accent = Color(red: 0.48, green: 0.88, blue: 0.44)
    static let surface = Color(red: 0.065, green: 0.095, blue: 0.085)
    static let surfaceRaised = Color(red: 0.085, green: 0.125, blue: 0.112)
    static let disabledSurface = Color(red: 0.075, green: 0.082, blue: 0.08)
    static let pillBackground = Color(red: 0.12, green: 0.16, blue: 0.145)
    static let stroke = Color.white.opacity(0.075)
    static let windowStroke = Color.white.opacity(0.12)
    static let track = Color.white.opacity(0.10)
    static let switchOff = Color.white.opacity(0.13)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.035, blue: 0.032),
                Color(red: 0.025, green: 0.058, blue: 0.052),
                Color(red: 0.012, green: 0.018, blue: 0.017)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

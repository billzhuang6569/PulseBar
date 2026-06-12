import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var sampler: MetricsSampler

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
        case 0..<45: Color(red: 0.15, green: 0.70, blue: 0.48)
        case 45..<72: Color(red: 0.24, green: 0.55, blue: 1.0)
        case 72..<88: Color(red: 0.96, green: 0.58, blue: 0.18)
        default: Color(red: 0.95, green: 0.22, blue: 0.28)
        }
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                header
                pressurePanel
                signalStrip

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(visibleReadings) { reading in
                            MetricTile(reading: reading)
                        }
                    }
                    .padding(.vertical, 2)
                }

                settingsPanel
                footer
            }
            .padding(12)
        }
        .frame(width: 348, height: 480)
        .onAppear {
            sampler.start(interval: preferences.refreshInterval)
        }
        .onChange(of: preferences.refreshInterval) { _, newValue in
            sampler.start(interval: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.45, blue: 1.0),
                                Color(red: 0.18, green: 0.78, blue: 0.58)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("庄Sir的状态栏")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("实时 Mac 状态")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(sampler.snapshot.capturedAt, style: .time)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var pressurePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pressureText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("综合内存、CPU 与硬盘压力")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(pressureValue.rounded()))")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(pressureColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [pressureColor.opacity(0.72), pressureColor],
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var signalStrip: some View {
        HStack(spacing: 6) {
            ForEach(MetricKind.allCases) { kind in
                if let reading = sampler.snapshot[kind] {
                    SignalPill(reading: reading, isFocused: preferences.menuBarKind == kind)
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("菜单栏焦点", systemImage: "menubar.rectangle")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Picker("菜单栏焦点", selection: $preferences.menuBarKind) {
                    ForEach(MetricKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 116)
            }

            HStack(spacing: 8) {
                Toggle("显示数值", isOn: $preferences.showPercentLabels)
                    .toggleStyle(.switch)
                    .font(.system(size: 12))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                    Slider(value: $preferences.refreshInterval, in: 1...5, step: 1)
                        .frame(width: 86)
                    Text("\(Int(preferences.refreshInterval))s")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 24, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(MetricKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { preferences.isEnabled(kind) },
                        set: { preferences.set(kind, enabled: $0) }
                    )) {
                        Label(kind.title, systemImage: kind.symbolName)
                            .foregroundStyle(kind.tint)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12))
                }
            }
        }
        .padding(11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                sampler.refresh()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct SignalPill: View {
    let reading: MetricReading
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: reading.kind.shortSymbolName)
                .font(.system(size: 12, weight: .bold))
            Text(reading.kind == .network ? reading.primaryText : MetricFormatter.compactPercent(reading.value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isFocused ? .white : reading.kind.tint)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isFocused ? reading.kind.tint : reading.kind.tint.opacity(0.12))
        )
    }
}

private struct MetricTile: View {
    let reading: MetricReading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: reading.kind.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(reading.kind.tint)
                    .frame(width: 17)

                Text(reading.kind.title)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()
            }

            Text(reading.primaryText)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            ProgressView(value: reading.value, total: 100)
                .tint(reading.kind.tint)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(reading.secondaryText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(reading.detailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(minHeight: 104, alignment: .top)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

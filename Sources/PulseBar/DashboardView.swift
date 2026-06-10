import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var sampler: MetricsSampler

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(MetricKind.allCases) { kind in
                            if let reading = sampler.snapshot[kind] {
                                MetricCard(reading: reading)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }

                settings
                footer
            }
            .padding(18)
        }
        .frame(width: 440, height: 610)
        .onAppear {
            sampler.start(interval: preferences.refreshInterval)
        }
        .onChange(of: preferences.refreshInterval) { _, newValue in
            sampler.start(interval: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("PulseBar")
                    .font(.system(size: 24, weight: .semibold))
                Text("菜单栏里的实时 Mac 状态")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(sampler.snapshot.capturedAt, style: .time)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("菜单栏显示", systemImage: "menubar.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Toggle("百分比标签", isOn: $preferences.showPercentLabels)
                    .toggleStyle(.switch)
                    .font(.system(size: 12))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Slider(value: $preferences.refreshInterval, in: 1...5, step: 1)
                Text("\(Int(preferences.refreshInterval))s")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 28, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
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
                Label("退出 PulseBar", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct MetricCard: View {
    let reading: MetricReading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: reading.kind.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(reading.kind.tint)
                    .frame(width: 24)

                Text(reading.kind.title)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Text(reading.primaryText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: reading.value, total: 100)
                .tint(reading.kind.tint)
                .controlSize(.small)

            HStack(alignment: .firstTextBaseline) {
                Text(reading.secondaryText)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(reading.detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
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

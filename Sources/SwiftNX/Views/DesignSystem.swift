import AppKit
import SwiftUI

enum Brand {
    static let accent = Color(red: 0.34, green: 0.47, blue: 1.0)
    static let mint = Color(red: 0.28, green: 0.85, blue: 0.68)
    static let warning = Color(red: 0.98, green: 0.69, blue: 0.24)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.40)
    static let purple = Color(red: 0.58, green: 0.38, blue: 0.98)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Brand.accent.opacity(0.09), Color.clear, Brand.purple.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct BrandMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.22, blue: 0.57),
                            Color(red: 0.32, green: 0.53, blue: 1.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Brand.accent.opacity(0.25), radius: size * 0.22, y: size * 0.08)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardSurface<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 22) -> some View {
        CardSurface(padding: padding) { self }
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = Brand.mint
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 0.7))
    }
}

struct IconTile: View {
    let symbol: String
    var color: Color = Brand.accent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

struct StepIndicator: View {
    let steps: [String]
    let current: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(index <= current ? Brand.accent : Color.primary.opacity(0.08))
                            .frame(width: 25, height: 25)
                        if index < current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(index == current ? .white : .secondary)
                        }
                    }
                    Text(title)
                        .font(.system(size: 12, weight: index == current ? .semibold : .regular))
                        .foregroundStyle(index == current ? .primary : .secondary)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < current ? Brand.accent.opacity(0.55) : Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }
            }
        }
    }
}

struct EnvironmentDot: View {
    let status: CheckStatus?

    var color: Color {
        switch status {
        case .ok: return Brand.mint
        case .warning: return Brand.warning
        case .missing, .blocked: return Brand.danger
        case nil: return .secondary.opacity(0.4)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 3)
    }
}

struct LogConsole: View {
    let lines: [LogLine]
    var maxHeight: CGFloat = 230
    var showHeader: Bool = true
    @State private var autoScroll = true

    private var visibleLines: ArraySlice<LogLine> {
        lines.suffix(1_200)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                HStack {
                    Label("Log", systemImage: "text.alignleft")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle(isOn: $autoScroll) {
                        Text("Follow")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.mini)
                    Button {
                        AppActions.copyToPasteboard(lines.map(\.text).joined(separator: "\n"))
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy the visible log")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.035))
                Divider().opacity(0.5)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(visibleLines) { line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(line.isError ? Brand.danger : Color.primary.opacity(0.78))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: maxHeight)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
                .onChange(of: lines.count) { _, _ in
                    guard autoScroll, let last = lines.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct EmptySymbol: View {
    let symbol: String
    var color: Color = Brand.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 86, height: 86)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

struct PathButtonRow: View {
    let title: String
    let path: String
    let systemImage: String
    var buttonTitle: String = "Choose…"
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: systemImage, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(path.isEmpty ? "Not set" : AppPaths.abbreviated(path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

struct LabeledValue: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

struct NativeVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

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

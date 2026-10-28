import SwiftUI

struct SetupLogView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        SetupLogContent(toolchain: app.toolchain)
    }
}

private struct SetupLogContent: View {
    @ObservedObject var toolchain: ToolchainManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill((toolchain.lastSucceeded ? Brand.mint : Brand.accent).opacity(0.12))
                        .frame(width: 42, height: 42)
                    if toolchain.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: toolchain.lastSucceeded ? "checkmark" : "wrench.and.screwdriver.fill")
                            .foregroundStyle(toolchain.lastSucceeded ? Brand.mint : Brand.accent)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(toolchain.title.isEmpty ? "Setup" : toolchain.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(toolchain.isRunning ? "Working…" : (toolchain.lastSucceeded ? "Finished" : "Finished with errors"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !toolchain.isRunning {
                    Button {
                        AppActions.copyToPasteboard(toolchain.lines.map(\.text).joined(separator: "\n"))
                    } label: {
                        Label("Copy Log", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)

            Divider().opacity(0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(toolchain.lines) { line in
                            Text(line.text)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(line.isError ? Brand.danger : Color.primary.opacity(0.8))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(14)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .onChange(of: toolchain.lines.count) { _, _ in
                    guard let last = toolchain.lines.last else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider().opacity(0.5)

            HStack {
                if let error = toolchain.lastError, !toolchain.isRunning {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.danger)
                        .lineLimit(2)
                }
                Spacer()
                Button(toolchain.isRunning ? "Please wait…" : "Close") {
                    toolchain.dismissLog()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
                .disabled(toolchain.isRunning)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 760, height: 500)
        .interactiveDismissDisabled(toolchain.isRunning)
    }
}

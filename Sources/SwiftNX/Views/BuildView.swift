import AppKit
import SwiftNXKit
import SwiftUI

struct BuildView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        BuildSheet(builder: app.builder, app: app)
    }
}

private struct BuildSheet: View {
    @ObservedObject var builder: BuildController
    @ObservedObject var app: AppModel
    @State private var showCancelConfirmation = false
    @State private var showCommand = false

    private var statusColor: Color {
        switch builder.state {
        case .succeeded: return Brand.mint
        case .failed: return Brand.danger
        case .cancelled: return Brand.warning
        case .idle: return .secondary
        default: return Brand.accent
        }
    }

    private var statusIcon: String {
        switch builder.state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        case .idle: return "circle"
        default: return "hammer.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    progressCard
                    if let entry = builder.finishedEntry, builder.state == .succeeded {
                        successCard(entry)
                    }
                    if builder.state == .failed {
                        failureCard
                    }
                    if !builder.stages.isEmpty {
                        stageList
                    }
                    if let message = builder.latestMessage, !message.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                            Text(message)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 4)
                    }
                    LogConsole(lines: builder.logLines, maxHeight: 210)
                    if let logFile = builder.logFileURL {
                        HStack(spacing: 8) {
                            Button {
                                AppActions.reveal(logFile)
                            } label: {
                                Label("Show full log", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10.5))
                            Text(AppPaths.abbreviate(logFile))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if !builder.command.isEmpty {
                        DisclosureGroup(isExpanded: $showCommand) {
                            Text(builder.command)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        } label: {
                            Label("Build command", systemImage: "terminal")
                                .font(.system(size: 10.5))
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(22)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 880, height: 700)
        .background(AppBackground())
        .interactiveDismissDisabled(builder.isRunning)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let entry = builder.finishedEntry, entry.exists {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                } else {
                    BrandMark(size: 48)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(builder.plan?.gameName ?? "nxnative build")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                HStack(spacing: 7) {
                    StatusPill(text: builder.statusTitle, color: statusColor, icon: statusIcon)
                    Text(builder.statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                if builder.isRunning {
                    showCancelConfirmation = true
                } else {
                    app.closeBuild()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help(builder.isRunning ? "Cancel the build before closing" : "Close")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var progressCard: some View {
        CardSurface(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Text("\(Int((builder.overallFraction * 100).rounded()))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(builder.currentStage?.name ?? (builder.state == .succeeded ? "Complete" : "Starting"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Label(BuildFormatting.duration(builder.elapsed), systemImage: "clock")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if let eta = builder.overallETA {
                        Text("ETA \(BuildFormatting.duration(eta))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                ProgressView(value: builder.overallFraction)
                    .progressViewStyle(.linear)
                    .tint(statusColor)
                    .scaleEffect(y: 1.35, anchor: .center)

                HStack {
                    if let stage = builder.currentStage {
                        Text("Stage \(stage.k) of \(max(stage.n, builder.totalStages))")
                        if let step = stage.step.nilIfEmpty {
                            Text("· \(step)")
                        }
                        if let count = stage.countText {
                            Text("· \(count)")
                        }
                        if let note = stage.note.nilIfEmpty {
                            Text("· \(note)")
                        }
                    } else {
                        Text(builder.state == .succeeded ? "The app is in your library." : "Waiting for nxnative…")
                    }
                    Spacer()
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pipeline")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(builder.stages.enumerated()), id: \.element.id) { index, stage in
                    StageRow(stage: stage, isLast: index == builder.stages.count - 1)
                    if index != builder.stages.count - 1 {
                        Divider().opacity(0.4).padding(.leading, 43)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func successCard(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(Brand.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.title) is ready")
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                app.open(entry)
            } label: {
                Label("Open Game", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(14)
        .background(Brand.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.mint.opacity(0.2), lineWidth: 1)
        )
    }

    private var failureCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 22))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text("nxnative stopped")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(builder.errorMessage ?? "Check the log for the failing step.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }
            Spacer()
            if let logFile = builder.logFileURL {
                Button {
                    AppActions.reveal(logFile)
                } label: {
                    Label("Open Log", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(Brand.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.2), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if builder.isRunning {
                Button {
                    showCancelConfirmation = true
                } label: {
                    Label("Stop Build", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(Brand.danger)
                .disabled(builder.state == .cancelling)
            } else if let entry = builder.finishedEntry, builder.state == .succeeded {
                Button {
                    app.reveal(entry)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if builder.state == .succeeded {
                Button("Start Another") {
                    app.startAnotherBuild()
                }
                .buttonStyle(.bordered)
                Button {
                    app.closeBuild()
                } label: {
                    Text("Done")
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if builder.state == .failed {
                Button("Close") {
                    app.closeBuild()
                }
                .buttonStyle(.bordered)
                Button {
                    app.startBuild()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            } else if builder.state == .cancelled {
                Button("Close") {
                    app.closeBuild()
                }
                .buttonStyle(.bordered)
                Button {
                    app.startAnotherBuild()
                } label: {
                    Label("Start Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(.bar)
        .confirmationDialog(
            "Stop this build?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Build", role: .destructive) {
                builder.cancel()
            }
            Button("Keep Building", role: .cancel) {}
        } message: {
            Text("nxnative will stop at the current step. Finished work stays cached, so the next build can reuse it.")
        }
    }
}

private struct StageRow: View {
    let stage: BuildStage
    let isLast: Bool

    private var color: Color {
        switch stage.status {
        case .succeeded: return Brand.mint
        case .failed: return Brand.danger
        case .running: return Brand.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.13))
                    .frame(width: 23, height: 23)
                switch stage.status {
                case .succeeded:
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                case .failed:
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(stage.name)
                        .font(.system(size: 11.5, weight: .medium))
                    Text("\(stage.k)/\(stage.n)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let elapsed = stage.elapsed {
                        Text(BuildFormatting.duration(elapsed))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if let summary = stage.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if stage.status == .running {
                    HStack(spacing: 7) {
                        if let step = stage.step.nilIfEmpty {
                            Text(step)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        if stage.fraction > 0 {
                            ProgressView(value: stage.fraction)
                                .progressViewStyle(.linear)
                                .tint(color)
                                .frame(maxWidth: 180)
                        }
                        if let count = stage.countText {
                            Text(count)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        if let note = stage.note.nilIfEmpty {
                            Text(note)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else if let step = stage.step.nilIfEmpty, stage.status == .failed {
                    Text(step)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

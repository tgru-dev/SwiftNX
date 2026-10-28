import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnvironmentView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        EnvironmentContent(
            environment: app.environment,
            settings: app.settings,
            toolchain: app.toolchain
        )
        .environmentObject(app)
    }
}

private struct EnvironmentContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var environment: EnvironmentModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var toolchain: ToolchainManager

    private var statusColor: Color {
        if environment.isChecking { return Brand.accent }
        if environment.ready { return environment.warningCount > 0 ? Brand.warning : Brand.mint }
        return Brand.danger
    }

    private var statusTitle: String {
        if environment.isChecking { return "Checking this Mac" }
        if environment.checks.isEmpty { return "Not checked yet" }
        if environment.ready { return environment.warningCount > 0 ? "Ready with notes" : "Ready to build" }
        return "Setup needed"
    }

    private var statusDetail: String {
        if environment.isChecking { return "Looking for Xcode, Metal, .NET, Homebrew and the Python environment…" }
        if environment.checks.isEmpty { return "Run a check to see what this Mac still needs." }
        if environment.ready {
            return "Everything needed for a Mac build is present. nxnative is driven by SwiftNX."
        }
        let blockers = environment.blockers
        return "\(blockers.count) required \(blockers.count == 1 ? "item needs" : "items need") attention before the first build."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 20) {
                    PageHeader(
                        title: "Environment",
                        subtitle: "A native check of the complete nxnative toolchain, set up without touching system Python."
                    )
                    Spacer()
                    Button {
                        environment.refresh()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(environment.isChecking)
                }

                heroCard

                ForEach(ToolCheck.Group.allCases, id: \.rawValue) { group in
                    let items = environment.checks.filter { $0.group == group }
                    if !items.isEmpty {
                        checkSection(group: group, items: items)
                    }
                }

                pathsCard

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                    Text("SwiftNX passes prod.keys directly to nxnative. Nothing is copied into the repository or uploaded.")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: 1_060, alignment: .leading)
        }
        .navigationTitle("Environment")
        .onAppear {
            if environment.checks.isEmpty { environment.refresh() }
        }
    }

    private var heroCard: some View {
        CardSurface {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                    if environment.isChecking || toolchain.isRunning {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: environment.ready ? "checkmark.seal.fill" : "wrench.and.screwdriver.fill")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(statusColor)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(statusTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(toolchain.isRunning ? (toolchain.title.isEmpty ? "Setting up…" : toolchain.title) : statusDetail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = toolchain.lastError, !toolchain.isRunning {
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Brand.danger)
                            .lineLimit(2)
                    }
                    if let checked = environment.lastChecked {
                        Text("Last checked \(checked.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 9) {
                    if environment.ready {
                        Button {
                            app.presentPort()
                        } label: {
                            Label("Port a Game", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button {
                            toolchain.installEverything()
                        } label: {
                            Label("Set Up Everything", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(toolchain.isRunning || environment.isChecking)
                        .help("Installs Homebrew formulae and creates SwiftNX's isolated Python environment")

                        if environment.check(id: "homebrew")?.status == .warning {
                            Button("Install Homebrew…") {
                                toolchain.openHomebrewInstaller()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func checkSection(group: ToolCheck.Group, items: [ToolCheck]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, check in
                    CheckRow(check: check) {
                        perform(check.action, for: check)
                    }
                    .disabled(toolchain.isRunning)
                    if index != items.count - 1 {
                        Divider().opacity(0.4).padding(.leading, 52)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private var pathsCard: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Paths")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    SettingsLink {
                        Text("Settings")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.link)
                }

                PathButtonRow(
                    title: "nxnative checkout",
                    path: settings.repositoryPath,
                    systemImage: "shippingbox.fill",
                    buttonTitle: "Choose…"
                ) {
                    app.chooseRepository()
                }
                PathButtonRow(
                    title: "prod.keys",
                    path: settings.keysPath,
                    systemImage: "key.fill",
                    buttonTitle: settings.keysPath.isEmpty ? "Choose…" : "Change…"
                ) {
                    app.chooseKeys()
                }
                PathButtonRow(
                    title: "Working folder",
                    path: settings.workingRoot,
                    systemImage: "externaldrive.fill",
                    buttonTitle: "Choose…"
                ) {
                    chooseDirectory(title: "Choose the working folder", current: settings.workingRoot) { path in
                        settings.workingRoot = path
                        app.port.workingRoot = path
                        settings.ensureDirectories()
                        environment.refresh()
                    }
                }
                PathButtonRow(
                    title: "Output folder",
                    path: settings.outputDirectory,
                    systemImage: "square.grid.2x2.fill",
                    buttonTitle: "Choose…"
                ) {
                    chooseDirectory(title: "Choose the output folder", current: settings.outputDirectory) { path in
                        settings.outputDirectory = path
                        app.port.outputDirectory = path
                        settings.ensureDirectories()
                    }
                }

                HStack(spacing: 14) {
                    Button {
                        settings.ensureDirectories()
                        AppActions.reveal(settings.outputDirectoryURL)
                    } label: {
                        Label("Show Library Folder", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))

                    Button {
                        AppActions.reveal(AppPaths.logsDirectory)
                    } label: {
                        Label("Show Logs", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
                }
                .padding(.top, 2)
            }
        }
    }

    private func perform(_ action: CheckAction?, for check: ToolCheck) {
        switch action {
        case .installHomebrew:
            toolchain.openHomebrewInstaller()
        case .installBrewTools:
            toolchain.installBrewTools()
        case .setupPython:
            toolchain.setupPython()
        case .installDotnet:
            toolchain.openDotnetInstaller()
        case .installMetalToolchain:
            toolchain.installMetalToolchain()
        case .openXcode:
            toolchain.openXcode()
        case .acceptXcodeLicense:
            toolchain.openXcodeLicense()
        case .cloneRepository:
            if check.id == "repo",
               FileManager.default.fileExists(atPath: settings.repositoryPath),
               !((try? FileManager.default.contentsOfDirectory(atPath: settings.repositoryPath)) ?? []).isEmpty {
                app.chooseRepository()
            } else {
                toolchain.cloneRepository()
            }
        case .chooseKeys:
            app.chooseKeys()
        case .none:
            break
        }
    }

    private func chooseDirectory(title: String, current: String, onChoose: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: AppPaths.expanded(current), isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(url.path)
        }
    }
}

private struct CheckRow: View {
    let check: ToolCheck
    let action: () -> Void

    private var color: Color {
        switch check.status {
        case .ok: return Brand.mint
        case .warning: return Brand.warning
        case .missing: return Brand.danger
        case .blocked: return Brand.danger
        }
    }

    private var icon: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .missing: return "circle.dashed"
        case .blocked: return "lock.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(check.title)
                        .font(.system(size: 12, weight: .semibold))
                    if !check.required && check.status != .ok {
                        Text("optional")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                }
                Text(check.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if let label = check.actionLabel, check.action != nil {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }
}

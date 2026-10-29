import AppKit
import SwiftNXKit
import SwiftUI
import UniformTypeIdentifiers

struct PortGameView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        PortContent(
            model: app.port,
            settings: app.settings,
            environment: app.environment
        )
        .environmentObject(app)
    }
}

private struct PortContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var model: PortGameModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var environment: EnvironmentModel

    private let stepTitles = ["Game files", "Port settings", "Review"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .bottom, spacing: 20) {
                        PageHeader(
                            title: "Port a Game",
                            subtitle: "One wizard for the whole nxnative pipeline: extract, rewrite, shaders, Metal, app."
                        )
                        Spacer()
                        StatusPill(
                            text: environment.ready ? "Environment ready" : "Setup needed",
                            color: environment.ready ? Brand.mint : Brand.warning,
                            icon: environment.ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                    }

                    StepIndicator(steps: stepTitles, current: model.step)
                        .padding(.vertical, 2)

                    if !environment.ready {
                        environmentBanner
                    }

                    switch model.step {
                    case 0:
                        filesStep
                    case 1:
                        settingsStep
                    default:
                        reviewStep
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 26)
                .frame(maxWidth: 1_060, alignment: .leading)
            }

            Divider().opacity(0.5)
            bottomBar
        }
        .navigationTitle("Port a Game")
        .onAppear {
            model.applyDefaults(settings: settings)
            model.profiles = environment.profiles
        }
        .onChange(of: environment.profiles) { _, profiles in
            model.profiles = profiles
        }
    }

    // MARK: - Step 1

    private var filesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select your own game files")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Base game and the matching update. Drop files onto a card or choose them; both stay where they are and SwiftNX links them into a working folder.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.chooseKeys()
                } label: {
                    Label(settings.keysPath.isEmpty ? "Choose prod.keys" : "prod.keys set", systemImage: "key")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 13) {
                PackageDropCard(
                    title: "Base game",
                    subtitle: "Required · NSP, XCI, NSZ or XCZ",
                    symbol: "shippingbox.fill",
                    color: Brand.accent,
                    inspected: model.base,
                    url: model.baseURL,
                    allowsClear: model.baseURL != nil,
                    onChoose: chooseBase,
                    onClear: { model.clearBase() },
                    onDropURL: acceptBase
                )

                PackageDropCard(
                    title: "Update",
                    subtitle: "Optional · use the matching release",
                    symbol: "arrow.down.circle.fill",
                    color: Brand.mint,
                    inspected: model.update,
                    url: model.updateURL,
                    allowsClear: model.updateURL != nil,
                    onChoose: chooseUpdate,
                    onClear: { model.setUpdate(nil) },
                    onDropURL: acceptUpdate
                )

                DLCDropCard(
                    urls: model.dlcURLs,
                    onChoose: chooseDLC,
                    onRemove: { model.removeDLC($0) },
                    onDropURLs: acceptDLC
                )
            }

            if let error = model.errorMessage {
                InlineMessage(
                    icon: "exclamationmark.triangle.fill",
                    color: Brand.danger,
                    title: "Check the selected files",
                    text: error
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("A base game and its update must be from the same release. DLC files are optional.")
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)

            PathButtonRow(
                title: "prod.keys",
                path: settings.keysPath,
                systemImage: "key.fill",
                buttonTitle: settings.keysPath.isEmpty ? "Choose…" : "Change…"
            ) {
                app.chooseKeys()
            }
            .padding(14)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .card(padding: 22)
    }

    // MARK: - Step 2

    private var settingsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            identityCard

            CardSurface {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Build settings")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(alignment: .top, spacing: 16) {
                        LabeledField(
                            title: "Game name",
                            text: Binding(
                                get: { model.gameName },
                                set: { model.gameName = $0; model.markGameNameEdited() }
                            ),
                            help: "Used for the working folder and the window title."
                        )
                        LabeledField(
                            title: "App name",
                            text: Binding(
                                get: { model.appName },
                                set: { model.appName = $0; model.markAppNameEdited() }
                            ),
                            help: "The name of the .app in your library."
                        )
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Game language")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $model.language) {
                                ForEach(GameLanguage.supported) { language in
                                    Text(language.name).tag(language.code)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Passed to nxnative as DM_LANG for the next build. The game app can change it later in its own settings.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Signing")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: settings.signIdentity.isEmpty ? "signature" : "checkmark.seal.fill")
                                    .foregroundStyle(settings.signIdentity.isEmpty ? .secondary : Brand.mint)
                                Text(settings.signIdentity.isEmpty ? "Ad-hoc (recommended)" : settings.signIdentity)
                                    .font(.system(size: 11.5))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                            Text("Change the identity in Settings.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Divider().opacity(0.5)

                    PathButtonRow(
                        title: "Working folder",
                        path: model.workingRoot,
                        systemImage: "externaldrive.fill",
                        buttonTitle: "Choose…"
                    ) {
                        chooseDirectory(
                            title: "Choose the working folder",
                            message: "nxnative keeps its build cache here. Expect large temporary files.",
                            current: model.workingRoot
                        ) { path in
                            model.workingRoot = path
                            settings.workingRoot = path
                        }
                    }

                    PathButtonRow(
                        title: "Output folder",
                        path: model.outputDirectory,
                        systemImage: "square.grid.2x2.fill",
                        buttonTitle: "Choose…"
                    ) {
                        chooseDirectory(
                            title: "Choose the output folder",
                            message: "The finished, self-contained Mac app is written here and added to your library.",
                            current: model.outputDirectory
                        ) { path in
                            model.outputDirectory = path
                            settings.outputDirectory = path
                        }
                    }
                }
            }

            profileCard
            issueList
        }
    }

    private var identityCard: some View {
        CardSurface {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Brand.accent.opacity(0.3), Brand.purple.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 78, height: 78)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.resolvedGameName)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        StatusPill(
                            text: model.profileSupportText,
                            color: model.matchedProfile == nil ? Brand.warning : Brand.mint,
                            icon: model.matchedProfile == nil ? "questionmark.circle" : "checkmark.seal.fill"
                        )
                        if let id = model.baseTitleID {
                            Text(id.hex)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let version = model.displayVersion {
                            Text("v\(version)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if let base = model.base {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(base.kind.displayName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(ByteCountFormatter.string(fromByteCount: base.fileSize, countStyle: .file))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var issueList: some View {
        let issues = model.issues(settings: settings)
        return Group {
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Checks")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }
        }
    }

    private var profileCard: some View {
        CardSurface(padding: 18) {
            HStack(alignment: .top, spacing: 13) {
                IconTile(
                    symbol: model.matchedProfile == nil ? "questionmark.diamond" : "checkmark.seal.fill",
                    color: model.matchedProfile == nil ? Brand.warning : Brand.mint,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.matchedProfile == nil ? "No matching profile" : "Game profile")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(model.profileSupportDetail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let profile = model.matchedProfile {
                        Text(AppPaths.abbreviate(profile.profileURL))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Step 3

    private var reviewStep: some View {
        let issues = model.issues(settings: settings)
        let hasErrors = issues.contains { $0.severity == .error }
        return VStack(alignment: .leading, spacing: 18) {
            CardSurface {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ready to build")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("nxnative builds in the background. You can keep using SwiftNX while it runs.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: hasErrors ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(hasErrors ? Brand.warning : Brand.mint)
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ], alignment: .leading, spacing: 16) {
                        LabeledValue(title: "Game", value: model.resolvedGameName)
                        LabeledValue(title: "App", value: model.resolvedAppName)
                        LabeledValue(title: "Language", value: model.selectedLanguage.name)
                        LabeledValue(title: "Title ID", value: model.baseTitleID?.hex ?? "Detected while building", monospaced: true)
                        LabeledValue(title: "Version", value: model.displayVersion ?? "Newest available")
                        LabeledValue(title: "Profile", value: model.matchedProfile?.name ?? "Provisional")
                        LabeledValue(title: "Base file", value: model.baseURL?.lastPathComponent ?? "—")
                        LabeledValue(title: "Update", value: model.updateURL?.lastPathComponent ?? "None")
                        LabeledValue(title: "Signing", value: settings.signIdentity.isEmpty ? "Ad-hoc" : settings.signIdentity)
                    }

                    Divider().opacity(0.5)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ], alignment: .leading, spacing: 14) {
                        LabeledValue(title: "Working folder", value: AppPaths.abbreviated(model.workingRoot), monospaced: true)
                        LabeledValue(title: "Output folder", value: AppPaths.abbreviated(model.outputDirectory), monospaced: true)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text("The first build takes 30–60 minutes and needs about twice the game size plus 10 GB.")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
            }

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Checks")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(issues) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }

            DisclosureGroup {
                LogPreview(text: model.planPreview(settings: settings))
                    .padding(.top, 8)
            } label: {
                Label("Command preview", systemImage: "terminal")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(16)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Navigation

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if model.step > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.step -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            if model.step < 2 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.step += 1 }
                } label: {
                    Label(model.step == 0 ? "Continue" : "Review", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.step == 0 && model.baseURL == nil)
            } else {
                if app.builder.isRunning {
                    Button {
                        app.showBuild = true
                    } label: {
                        Label("Show Build", systemImage: "chart.bar.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        _ = app.startBuild()
                    } label: {
                        Label("Start Build", systemImage: "hammer.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.issues(settings: settings).contains { $0.severity == .error } || !environment.ready)
                    .help(environment.ready ? "Start the nxnative build" : "Complete the Environment setup first")
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 13)
        .background(.bar)
    }

    private var environmentBanner: some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: environment.isChecking ? "hourglass" : "wrench.and.screwdriver.fill",
                color: Brand.warning,
                size: 34
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(environment.isChecking ? "Checking this Mac…" : "Finish setting up your Mac")
                    .font(.system(size: 12, weight: .semibold))
                Text(environment.blockers.first?.detail.components(separatedBy: .newlines).first
                     ?? "Some required tools are missing. The build needs Xcode, Metal, .NET 10 and the Python environment.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Open Environment") {
                app.selection = .environment
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(13)
        .background(Brand.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Pickers

    private func packageTypes() -> [UTType] {
        ["nsp", "xci", "nsz", "xcz"].map { UTType(filenameExtension: $0) ?? .data }
    }

    private func chooseBase() {
        choosePackage(title: "Choose the base game", message: "Select the base game dump (NSP, XCI, NSZ or XCZ).") { url in
            acceptBase(url)
        }
    }

    private func chooseUpdate() {
        choosePackage(title: "Choose the update", message: "Select the matching update for this base game.") { url in
            acceptUpdate(url)
        }
    }

    private func chooseDLC() {
        let panel = NSOpenPanel()
        panel.title = "Add DLC files"
        panel.message = "Select one or more DLC packages. They are optional."
        panel.allowedContentTypes = packageTypes()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            acceptDLC(panel.urls)
        }
    }

    private func acceptDLC(_ urls: [URL]) {
        let packages = urls.filter { PackageFileKind(url: $0) != nil }
        guard !packages.isEmpty else {
            model.errorMessage = "Drop one or more NSP, XCI, NSZ or XCZ files for DLC."
            return
        }
        if model.errorMessage?.hasPrefix("Drop one or more") == true {
            model.errorMessage = nil
        }
        model.addDLC(packages)
    }

    private func choosePackage(title: String, message: String, onChoose: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.allowedContentTypes = packageTypes()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(url)
        }
    }

    private func acceptBase(_ url: URL) {
        guard PackageFileKind(url: url) != nil else {
            model.errorMessage = "Choose an NSP, XCI, NSZ or XCZ file."
            return
        }
        model.setBase(url)
        if model.appName.isEmpty { model.appName = model.resolvedAppName }
    }

    private func acceptUpdate(_ url: URL) {
        guard PackageFileKind(url: url) != nil else {
            model.errorMessage = "Choose an NSP, XCI, NSZ or XCZ file."
            return
        }
        model.setUpdate(url)
    }

    private func chooseDirectory(
        title: String,
        message: String,
        current: String,
        onChoose: @escaping (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
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

// MARK: - Supporting views

private struct PackageDropCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let inspected: InspectedPackage?
    let url: URL?
    let allowsClear: Bool
    let onChoose: () -> Void
    let onClear: () -> Void
    let onDropURL: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if allowsClear {
                    Button("Remove") { onClear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let inspected, let url {
                HStack(spacing: 12) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                        .frame(width: 38, height: 48)
                        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(inspected.kind.displayName)
                            Text("·")
                            Text(ByteCountFormatter.string(fromByteCount: inspected.fileSize, countStyle: .file))
                            if let id = inspected.titleID {
                                Text("·")
                                Text(id.hex)
                                    .font(.system(size: 9.5, design: .monospaced))
                            }
                            if let version = inspected.version {
                                Text("·")
                                Text("v\(version)")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change…", action: onChoose)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Button(action: onChoose) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(color.opacity(0.9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drop a file here, or choose one")
                                .font(.system(size: 12, weight: .medium))
                            Text("NSP · XCI · NSZ · XCZ")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "hand.tap")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isTargeted ? color.opacity(0.12) : Color.primary.opacity(0.025))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isTargeted ? color.opacity(0.65) : Color.primary.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard !providers.isEmpty else { return false }
            DroppedFiles.load(from: providers) { dropped in
                if let first = dropped.first {
                    onDropURL(first)
                }
            }
            return true
        }
    }
}

private struct DLCDropCard: View {
    let urls: [URL]
    let onChoose: () -> Void
    let onRemove: (URL) -> Void
    let onDropURLs: ([URL]) -> Void

    @State private var isTargeted = false

    private var packageCountText: String {
        "\(urls.count) package\(urls.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(Brand.purple)
                Text("DLC")
                    .font(.system(size: 12, weight: .semibold))
                Text(urls.isEmpty ? "Optional · multiple packages" : packageCountText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(urls.isEmpty ? "Choose…" : "Add more…", action: onChoose)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if urls.isEmpty {
                Button(action: onChoose) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Brand.purple.opacity(0.9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drop DLC files here, or choose them")
                                .font(.system(size: 12, weight: .medium))
                            Text("NSP · XCI · NSZ · XCZ · multiple files allowed")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "hand.tap")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isTargeted ? Brand.purple.opacity(0.12) : Color.primary.opacity(0.025))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isTargeted ? Brand.purple.opacity(0.65) : Color.primary.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 6) {
                    ForEach(urls, id: \.self) { url in
                        HStack(spacing: 9) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .foregroundStyle(Brand.purple)
                            Text(url.lastPathComponent)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                onRemove(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isTargeted ? Brand.purple.opacity(0.06) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Brand.purple.opacity(0.55) : Color.primary.opacity(0.08),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )

                Text("Drop more DLC files here, or use Add more…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(isTargeted ? Brand.purple : Color.secondary)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard !providers.isEmpty else { return false }
            DroppedFiles.load(from: providers) { dropped in
                if !dropped.isEmpty {
                    onDropURLs(dropped)
                }
            }
            return true
        }
    }
}

private enum DroppedFiles {
    static func load(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls = Array<URL?>(repeating: nil, count: providers.count)

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let path = item as? String {
                    url = URL(fileURLWithPath: path)
                } else {
                    url = nil
                }

                if let url {
                    lock.lock()
                    urls[index] = url
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            completion(urls.compactMap { $0 })
        }
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var text: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Text(help)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IssueRow: View {
    let issue: PortIssue

    private var color: Color {
        switch issue.severity {
        case .error: return Brand.danger
        case .warning: return Brand.warning
        case .info: return Brand.accent
        }
    }

    private var icon: String {
        switch issue.severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(issue.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(11)
        .background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct InlineMessage: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(11)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct LogPreview: View {
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            Button {
                AppActions.copyToPasteboard(text)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10.5))
        }
    }
}

private extension PortGameModel {
    func planPreview(settings: AppSettings) -> String {
        guard let baseURL else { return "Choose a base game to see the command." }
        let folderID = baseTitleID?.hex ?? ""
        var name = AppPaths.sanitizeFilename(resolvedGameName)
        if !folderID.isEmpty { name += " [\(folderID)]" }
        let staging = URL(fileURLWithPath: AppPaths.expanded(workingRoot)).appendingPathComponent(name).path
        let app = URL(fileURLWithPath: AppPaths.expanded(outputDirectory))
            .appendingPathComponent(AppPaths.sanitizeFilename(resolvedAppName) + ".app").path
        var args = [
            AppPaths.pythonExecutable.path,
            settings.repositoryURL.appendingPathComponent("scripts/build_ipa_from_nsp.py").path,
            staging,
            "-k", settings.keysPath,
            "--platform", "mac-app",
            "--progress", "json",
            "-l", selectedLanguage.code,
            "-o", app,
            "--app-name", resolvedAppName,
        ]
        if !settings.signIdentity.isEmpty {
            args.append(contentsOf: ["--mac-sign", settings.signIdentity])
        }
        _ = baseURL
        return "cd \(StreamingProcess.shellQuote(settings.repositoryURL.path))\n"
            + args.map(StreamingProcess.shellQuote).joined(separator: " ")
    }
}

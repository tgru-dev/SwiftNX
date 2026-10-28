import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        SettingsContent(settings: app.settings)
            .environmentObject(app)
            .frame(width: 650, height: 660)
    }
}

private struct SettingsContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var settings: AppSettings

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                BrandMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SwiftNX Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Paths, language and signing")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.refreshAll()
                } label: {
                    Label("Recheck", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.bar)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsGroup("nxnative") {
                        pathField(
                            title: "Repository",
                            text: $settings.repositoryPath,
                            help: "The checkout containing scripts/build_ipa_from_nsp.py.",
                            choose: chooseRepository
                        )
                        pathField(
                            title: "prod.keys",
                            text: $settings.keysPath,
                            help: "Dumped from your own console. nxnative reads it for each build.",
                            choose: chooseKeys
                        )
                    }

                    settingsGroup("Build") {
                        pathField(
                            title: "Working folder",
                            text: $settings.workingRoot,
                            help: "Game staging folders and the reusable nxnative build cache.",
                            choose: { chooseDirectory("Choose the working folder", into: $settings.workingRoot) }
                        )
                        pathField(
                            title: "Output folder",
                            text: $settings.outputDirectory,
                            help: "Finished, self-contained .app bundles are written here.",
                            choose: { chooseDirectory("Choose the output folder", into: $settings.outputDirectory) }
                        )

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Game language")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $settings.language) {
                                    ForEach(GameLanguage.supported) { language in
                                        Text(language.name).tag(language.code)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 220, alignment: .leading)
                            }
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Signing identity")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("Ad-hoc (leave empty)", text: $settings.signIdentity)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Text("Optional: a Developer ID Application identity. Ad-hoc signing is what nxnative recommends for local builds.")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    settingsGroup("Xcode") {
                        pathField(
                            title: "Xcode app",
                            text: $settings.xcodePath,
                            help: "SwiftNX sets DEVELOPER_DIR for nxnative, so xcode-select can stay on Command Line Tools.",
                            choose: chooseXcode
                        )
                        HStack(spacing: 10) {
                            Button("Install Metal Toolchain") {
                                app.toolchain.installMetalToolchain()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Accept Xcode License…") {
                                app.toolchain.openXcodeLicense()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    settingsGroup("Maintenance") {
                        HStack(spacing: 10) {
                            Button("Reset Paths") {
                                settings.resetPaths()
                                app.environment.refresh()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Show Application Support") {
                                AppActions.reveal(AppPaths.supportDirectory)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Open Logs") {
                                AppActions.reveal(AppPaths.logsDirectory)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SwiftNX \(version)")
                            .font(.system(size: 10, weight: .semibold))
                        Text("A native frontend for nxnative (MIT). SwiftNX does not include game data or keys. Nintendo Switch is a trademark of Nintendo; this project is not affiliated with Nintendo.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .padding(24)
            }
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func pathField(
        title: String,
        text: Binding<String>,
        help: String,
        choose: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10.5, design: .monospaced))
                Button("Choose…", action: choose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text(help)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose the nxnative checkout"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.repositoryPath = url.path
            app.port.profiles = app.environment.profiles
            app.environment.refresh()
        }
    }

    private func chooseKeys() {
        let panel = NSOpenPanel()
        panel.title = "Choose prod.keys"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.keysPath = url.path
            app.port.keysPath = url.path
            app.environment.refresh()
        }
    }

    private func chooseDirectory(_ title: String, into binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }

    private func chooseXcode() {
        let panel = NSOpenPanel()
        panel.title = "Choose Xcode.app"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        if panel.runModal() == .OK, let url = panel.url {
            settings.xcodePath = url.path
            app.environment.refresh()
        }
    }
}

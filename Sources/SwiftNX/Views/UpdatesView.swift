import SwiftUI

struct UpdatesView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        UpdatesContent(updater: app.updater, settings: app.settings)
            .environmentObject(app)
    }
}

private struct UpdatesContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var updater: RepoUpdater
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 20) {
                    PageHeader(
                        title: "Updates",
                        subtitle: "Keep the nxnative engine current without touching your SwiftNX settings or library."
                    )
                    Spacer()
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(updater.isWorking)
                }

                if !updater.repositoryExists {
                    missingCard
                } else if let info = updater.info {
                    repositoryCard(info)
                    updateCard(info)
                } else {
                    CardSurface {
                        HStack(spacing: 14) {
                            if updater.isWorking { ProgressView() } else { IconTile(symbol: "questionmark.folder", color: Brand.warning) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No Git checkout at this path")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(settings.repositoryPath)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if let message = updater.message {
                                    Text(message)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Choose Folder…") { app.chooseRepository() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                if let message = updater.message {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Brand.accent)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Brand.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                CardSurface(padding: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("How SwiftNX updates", systemImage: "lock.doc")
                            .font(.system(size: 12, weight: .semibold))
                        Text("SwiftNX clones nxnative on first launch and checks the newest upstream commit every time the app starts. Existing checkouts are fast-forwarded only: local changes are never discarded. Your paths, keys location and game library live in SwiftNX's own Application Support folder, and build caches stay in the working folders.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            Button {
                                AppActions.open(URL(string: "https://github.com/seedds/nxnative")!)
                            } label: {
                                Label("Open nxnative on GitHub", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10.5))
                            Button {
                                AppActions.reveal(settings.repositoryURL)
                            } label: {
                                Label("Show Checkout", systemImage: "folder")
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10.5))
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: 1_060, alignment: .leading)
        }
        .navigationTitle("Updates")
        .onAppear {
            if updater.info == nil { updater.refresh() }
        }
    }

    private var missingCard: some View {
        CardSurface {
            HStack(alignment: .top, spacing: 16) {
                EmptySymbol(symbol: "shippingbox", color: Brand.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clone nxnative")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("SwiftNX uses the open-source nxnative repository as its porting engine. It normally downloads the checkout into \(AppPaths.abbreviated(settings.repositoryPath)) automatically on launch; you can also clone it here.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            app.toolchain.cloneRepository()
                        } label: {
                            Label("Clone Repository", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Choose Existing Folder…") {
                            app.chooseRepository()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 5)
                }
                Spacer()
            }
        }
    }

    private func repositoryCard(_ info: RepoInfo) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    IconTile(symbol: "shippingbox.fill", color: Brand.accent, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("nxnative")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            StatusPill(
                                text: info.dirty ? "Local changes" : "Clean checkout",
                                color: info.dirty ? Brand.warning : Brand.mint,
                                icon: info.dirty ? "pencil.circle" : "checkmark.circle"
                            )
                            if info.behind > 0 {
                                StatusPill(text: "\(info.behind) behind", color: Brand.warning, icon: "arrow.down")
                            } else if info.ahead > 0 {
                                StatusPill(text: "\(info.ahead) ahead", color: Brand.accent, icon: "arrow.up")
                            } else {
                                StatusPill(text: "Up to date", color: Brand.mint, icon: "checkmark")
                            }
                        }
                        Text(info.remote ?? "No remote configured")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        updater.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updater.isWorking)
                }

                Divider().opacity(0.5)

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
                ], alignment: .leading, spacing: 14) {
                    LabeledValue(title: "Branch", value: info.branch, monospaced: true)
                    LabeledValue(title: "Commit", value: info.commit, monospaced: true)
                    LabeledValue(title: "Commit date", value: info.commitDate.isEmpty ? "—" : info.commitDate)
                    LabeledValue(title: "Path", value: AppPaths.abbreviate(settings.repositoryURL))
                }

                if !info.subject.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(info.subject)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func updateCard(_ info: RepoInfo) -> some View {
        CardSurface {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: info.behind > 0 ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(info.behind > 0 ? Brand.warning : Brand.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.behind > 0
                         ? "\(info.behind) upstream commit\(info.behind == 1 ? "" : "s") ready"
                         : "The engine is current")
                        .font(.system(size: 14, weight: .semibold))
                    Text(info.behind > 0
                         ? "Update with a fast-forward pull. Builds will reuse their caches where the inputs are unchanged."
                         : "Check again after the nxnative project publishes new work.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if updater.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else if info.behind > 0 {
                    Button {
                        updater.update()
                    } label: {
                        Label("Update nxnative", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(info.dirty)
                    .help(info.dirty ? "Commit or stash your changes in the checkout first" : "Fast-forward to the upstream branch")
                } else {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

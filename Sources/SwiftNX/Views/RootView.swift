import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 224, ideal: 242, max: 280)
        } detail: {
            ZStack {
                AppBackground()
                detailView
            }
            .navigationSplitViewColumnWidth(min: 760, ideal: 960)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Brand.accent)
        .frame(minWidth: 1_040, minHeight: 680)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.presentPort()
                } label: {
                    Label("Port a Game", systemImage: "plus")
                }
                .help("Port a game with nxnative")
            }
        }
        .sheet(isPresented: $app.showBuild) {
            BuildView()
                .environmentObject(app)
        }
        .sheet(isPresented: $app.showWelcome) {
            WelcomeView()
                .environmentObject(app)
        }
        .sheet(isPresented: Binding(
            get: { app.toolchain.isLogPresented },
            set: { if !$0 { app.toolchain.dismissLog() } }
        )) {
            SetupLogView()
                .environmentObject(app)
        }
        .onAppear {
            app.settings.ensureDirectories()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch app.selection ?? .library {
        case .library:
            LibraryView()
        case .port:
            PortGameView()
        case .environment:
            EnvironmentView()
        case .updates:
            UpdatesView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var app: AppModel

    private var environmentStatus: CheckStatus? {
        if app.environment.isChecking { return nil }
        if app.environment.checks.isEmpty { return nil }
        if app.environment.blockers.isEmpty {
            return app.environment.warningCount > 0 ? .warning : .ok
        }
        return .blocked
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SwiftNX")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("nxnative, natively")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            List(selection: $app.selection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(app.selection == item ? Brand.accent : .secondary)
                                .frame(width: 19)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                Text(item.subtitle)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.5)
            VStack(spacing: 9) {
                Button {
                    app.selection = .environment
                } label: {
                    HStack(spacing: 8) {
                        EnvironmentDot(status: environmentStatus)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.environment.summary)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(app.environment.isChecking ? "Checking tools…" : "Environment")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack {
                    Button("nxnative on GitHub") {
                        if let url = URL(string: "https://github.com/seedds/nxnative") {
                            AppActions.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 9.5))
                    Spacer()
                    Text("v1.0")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(.thinMaterial)
    }
}

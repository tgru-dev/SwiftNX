import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        LibraryContent(library: app.library, environment: app.environment)
            .environmentObject(app)
    }
}

private struct LibraryContent: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var library: LibraryStore
    @ObservedObject var environment: EnvironmentModel
    @State private var search = ""

    private var filtered: [LibraryEntry] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return library.entries }
        let query = search.lowercased()
        return library.entries.filter {
            $0.title.lowercased().contains(query)
                || ($0.titleID?.lowercased().contains(query) ?? false)
                || ($0.profileName?.lowercased().contains(query) ?? false)
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 225, maximum: 300), spacing: 18, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 20) {
                    PageHeader(
                        title: "Library",
                        subtitle: library.entries.isEmpty
                            ? "Your ported Mac games will live here."
                            : "\(library.entries.count) ported \(library.entries.count == 1 ? "game" : "games"), ready to play."
                    )
                    Spacer(minLength: 20)
                    SearchField(text: $search)
                        .frame(width: 235)
                }

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(filtered) { entry in
                            GameCard(
                                entry: entry,
                                open: { app.open(entry) },
                                reveal: { app.reveal(entry) },
                                remove: { library.remove(entry) }
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 10))
                    Text("SwiftNX contains no games or keys. Use dumps and prod.keys from your own Nintendo Switch.")
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(maxWidth: 1_200, alignment: .leading)
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Button {
                    if let path = library.entries.first?.url.deletingLastPathComponent() {
                        AppActions.reveal(path)
                    } else {
                        app.settings.ensureDirectories()
                        AppActions.reveal(app.settings.outputDirectoryURL)
                    }
                } label: {
                    Label("Show Library Folder", systemImage: "folder")
                }
                .help("Show the folder containing the built apps")
            }
        }
    }

    private var emptyState: some View {
        CardSurface(padding: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    EmptySymbol(symbol: "gamecontroller")
                    VStack(spacing: 7) {
                        Text(search.isEmpty ? "Your library is empty" : "No games match “\(search)”")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                        Text(search.isEmpty
                             ? "Pick a base game and its update, then let SwiftNX drive the entire nxnative build."
                             : "Try another title, title ID or profile name.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 10) {
                        Button {
                            app.presentPort()
                        } label: {
                            Label("Port a Game", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            app.selection = .environment
                        } label: {
                            Label(environment.ready ? "Environment" : "Set Up Environment", systemImage: "wrench.and.screwdriver")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 54)
                .padding(.horizontal, 30)

                Divider().opacity(0.5)
                HStack(spacing: 26) {
                    FeatureNote(icon: "lock.shield", title: "Stays local", text: "Keys and dumps stay on this Mac.")
                    FeatureNote(icon: "bolt.fill", title: "Real app", text: "Self-contained, signed by nxnative.")
                    FeatureNote(icon: "chart.bar.fill", title: "Live progress", text: "Stages, ETA and the full log.")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(Color.primary.opacity(0.025))
            }
        }
    }
}

private struct FeatureNote: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search library", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        )
    }
}

private struct GameCard: View {
    let entry: LibraryEntry
    let open: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: entry.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Brand.accent.opacity(0.24),
                                Brand.purple.opacity(0.18),
                                Color.primary.opacity(0.035),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1.45, contentMode: .fit)
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !entry.exists {
                    StatusPill(text: "Missing", color: Brand.danger, icon: "exclamationmark.triangle.fill")
                        .padding(9)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let version = entry.version {
                        Text("v\(version)")
                    }
                    if let titleID = entry.titleID {
                        Text(titleID)
                            .font(.system(size: 9.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: open) {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!entry.exists)

                Button(action: reveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show in Finder")
                .disabled(!entry.exists)

                Menu {
                    Button("Show in Finder", action: reveal).disabled(!entry.exists)
                    Button("Copy Title ID") {
                        if let id = entry.titleID { AppActions.copyToPasteboard(id) }
                    }
                    .disabled(entry.titleID == nil)
                    Divider()
                    Button("Remove from Library…", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
            .opacity(entry.exists ? 1 : 0.6)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(hovering ? Brand.accent.opacity(0.38) : Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.09 : 0.045), radius: hovering ? 18 : 10, y: 6)
        .scaleEffect(hovering ? 1.008 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: open)
        .contextMenu {
            Button("Play", action: open).disabled(!entry.exists)
            Button("Show in Finder", action: reveal).disabled(!entry.exists)
            Divider()
            Button("Remove from Library…", role: .destructive, action: remove)
        }
    }
}

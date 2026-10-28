import SwiftUI

@main
struct SwiftNXApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1_180, height: 790)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Port a Game…") {
                    app.presentPort()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Refresh Environment") {
                    app.refreshAll()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Build") {
                Button("Start Build") {
                    _ = app.startBuild()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(app.port.baseURL == nil || app.builder.isRunning)
                Divider()
                Button("Show Environment") {
                    app.selection = .environment
                }
                Button("Show Library") {
                    app.selection = .library
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}

import AppKit
import Combine
import Foundation
import SwiftNXKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case library
    case port
    case environment
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .port: return "Port a Game"
        case .environment: return "Environment"
        case .updates: return "Updates"
        }
    }

    var icon: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .port: return "wand.and.stars"
        case .environment: return "wrench.and.screwdriver"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var subtitle: String {
        switch self {
        case .library: return "Your ported games"
        case .port: return "Turn a dump into an app"
        case .environment: return "Xcode, tools, Python"
        case .updates: return "nxnative checkout"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let environment: EnvironmentModel
    let library: LibraryStore
    let port: PortGameModel
    let builder: BuildController
    let updater: RepoUpdater
    let toolchain: ToolchainManager

    @Published var selection: SidebarItem? = .library
    @Published var showBuild = false
    @Published var showWelcome: Bool

    private var cancellables = Set<AnyCancellable>()

    init() {
        AppPaths.prepare()
        let settings = AppSettings()
        self.settings = settings
        self.library = LibraryStore()
        self.environment = EnvironmentModel(settings: settings)
        self.port = PortGameModel()
        self.builder = BuildController()
        self.updater = RepoUpdater(settings: settings)
        self.toolchain = ToolchainManager(settings: settings)
        self.showWelcome = !settings.hasCompletedOnboarding

        port.applyDefaults(settings: settings)
        port.profiles = environment.profiles

        environment.$profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] profiles in
                self?.port.profiles = profiles
            }
            .store(in: &cancellables)

        settings.$keysPath
            .receive(on: RunLoop.main)
            .sink { [weak self] path in
                guard let self, !path.isEmpty else { return }
                self.port.keysPath = path
            }
            .store(in: &cancellables)

        settings.$workingRoot
            .receive(on: RunLoop.main)
            .sink { [weak self] path in
                guard let self, !path.isEmpty else { return }
                self.port.workingRoot = path
            }
            .store(in: &cancellables)

        settings.$outputDirectory
            .receive(on: RunLoop.main)
            .sink { [weak self] path in
                guard let self, !path.isEmpty else { return }
                self.port.outputDirectory = path
            }
            .store(in: &cancellables)

        settings.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] code in
                guard let self, !code.isEmpty else { return }
                self.port.language = code
            }
            .store(in: &cancellables)

        toolchain.onFinished = { [weak self] in
            self?.environment.refresh()
            self?.updater.refresh()
        }

        Task { [weak self] in
            self?.environment.refresh()
            self?.updater.refresh()
        }
    }

    func refreshAll() {
        environment.refresh()
        updater.refresh()
    }

    func presentPort() {
        port.applyDefaults(settings: settings)
        if port.baseURL == nil { port.step = 0 }
        selection = .port
    }

    @discardableResult
    func startBuild() -> Bool {
        if !environment.checks.isEmpty, !environment.ready {
            port.errorMessage = "Finish the Environment setup before starting a build. \(environment.blockers.first?.title ?? "A required tool is missing.")"
            selection = .environment
            return false
        }
        do {
            let plan = try port.preparePlan(settings: settings)
            builder.start(plan: plan, settings: settings) { [weak self] entry in
                self?.library.upsert(entry)
            }
            showBuild = true
            return true
        } catch {
            port.errorMessage = error.localizedDescription
            return false
        }
    }

    func closeBuild() {
        guard !builder.isRunning else { return }
        showBuild = false
        if builder.state == .succeeded {
            selection = .library
        }
    }

    func startAnotherBuild() {
        guard !builder.isRunning else { return }
        builder.reset()
        showBuild = false
        port.step = 0
        selection = .port
    }

    func completeWelcome(setup: Bool) {
        settings.hasCompletedOnboarding = true
        showWelcome = false
        if setup {
            selection = .environment
            environment.refresh()
        } else {
            selection = .library
        }
    }

    func open(_ entry: LibraryEntry) {
        guard entry.exists else { return }
        AppActions.openApp(entry.url)
    }

    func reveal(_ entry: LibraryEntry) {
        guard entry.exists else { return }
        AppActions.reveal(entry.url)
    }

    func chooseKeys() {
        let panel = NSOpenPanel()
        panel.title = "Choose prod.keys"
        panel.message = "Select the prod.keys dumped from your own Nintendo Switch. The file is passed to nxnative and never uploaded."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.keysPath = url.path
            port.keysPath = url.path
            environment.refresh()
        }
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose the nxnative checkout"
        panel.message = "Select the folder containing scripts/build_ipa_from_nsp.py."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.repositoryPath = url.path
            environment.refresh()
            updater.refresh()
        }
    }
}

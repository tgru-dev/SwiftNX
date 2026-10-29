import Foundation
import SwiftUI

struct GameLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }

    // Kept in the same order and with the same codes as nxnative's NACP table.
    static let supported: [GameLanguage] = [
        .init(code: "en-US", name: "American English"),
        .init(code: "en-GB", name: "British English"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "es-419", name: "Latin American Spanish"),
        .init(code: "es", name: "Spanish"),
        .init(code: "it", name: "Italian"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "fr-CA", name: "Canadian French"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "ru", name: "Russian"),
        .init(code: "ko", name: "Korean"),
        .init(code: "zh-Hant", name: "Traditional Chinese"),
        .init(code: "zh-Hans", name: "Simplified Chinese"),
        .init(code: "pt-BR", name: "Brazilian Portuguese"),
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let repository = "settings.repositoryPath"
        static let keys = "settings.keysPath"
        static let workingRoot = "settings.workingRoot"
        static let outputDirectory = "settings.outputDirectory"
        static let language = "settings.language"
        static let signIdentity = "settings.signIdentity"
        static let xcodePath = "settings.xcodePath"
        static let onboarded = "settings.hasCompletedOnboarding"
    }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    @Published var repositoryPath: String { didSet { save() } }
    @Published var keysPath: String { didSet { save() } }
    @Published var workingRoot: String { didSet { save() } }
    @Published var outputDirectory: String { didSet { save() } }
    @Published var language: String { didSet { save() } }
    @Published var signIdentity: String { didSet { save() } }
    @Published var xcodePath: String { didSet { save() } }
    @Published var hasCompletedOnboarding: Bool { didSet { save() } }

    init() {
        defaults.register(defaults: [
            Key.repository: AppPaths.defaultRepository.path,
            Key.keys: "",
            Key.workingRoot: AppPaths.defaultWorkingRoot.path,
            Key.outputDirectory: AppPaths.defaultOutputDirectory.path,
            Key.language: "en-US",
            Key.signIdentity: "",
            Key.xcodePath: "/Applications/Xcode.app",
            Key.onboarded: false,
        ])
        repositoryPath = defaults.string(forKey: Key.repository) ?? AppPaths.defaultRepository.path
        let savedKeysPath = defaults.string(forKey: Key.keys) ?? ""
        keysPath = savedKeysPath.isEmpty && FileManager.default.fileExists(atPath: AppPaths.defaultKeysFile.path)
            ? AppPaths.defaultKeysFile.path
            : savedKeysPath
        workingRoot = defaults.string(forKey: Key.workingRoot) ?? AppPaths.defaultWorkingRoot.path
        outputDirectory = defaults.string(forKey: Key.outputDirectory) ?? AppPaths.defaultOutputDirectory.path
        language = defaults.string(forKey: Key.language) ?? "en-US"
        signIdentity = defaults.string(forKey: Key.signIdentity) ?? ""
        xcodePath = defaults.string(forKey: Key.xcodePath) ?? "/Applications/Xcode.app"
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarded)
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(repositoryPath, forKey: Key.repository)
        defaults.set(keysPath, forKey: Key.keys)
        defaults.set(workingRoot, forKey: Key.workingRoot)
        defaults.set(outputDirectory, forKey: Key.outputDirectory)
        defaults.set(language, forKey: Key.language)
        defaults.set(signIdentity, forKey: Key.signIdentity)
        defaults.set(xcodePath, forKey: Key.xcodePath)
        defaults.set(hasCompletedOnboarding, forKey: Key.onboarded)
    }

    var repositoryURL: URL { AppPaths.url(repositoryPath) }
    var keysURL: URL? {
        keysPath.isEmpty ? nil : AppPaths.url(keysPath)
    }
    var workingRootURL: URL { AppPaths.url(workingRoot) }
    var outputDirectoryURL: URL { AppPaths.url(outputDirectory) }
    var xcodeURL: URL { AppPaths.url(xcodePath) }

    var selectedLanguage: GameLanguage {
        GameLanguage.supported.first { $0.code == language }
            ?? GameLanguage.supported[0]
    }

    func ensureDirectories() {
        for url in [workingRootURL, outputDirectoryURL, AppPaths.supportDirectory, AppPaths.logsDirectory, AppPaths.keysDirectory] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: AppPaths.keysDirectory.path
        )
    }

    func resetPaths() {
        repositoryPath = AppPaths.defaultRepository.path
        workingRoot = AppPaths.defaultWorkingRoot.path
        outputDirectory = AppPaths.defaultOutputDirectory.path
        xcodePath = "/Applications/Xcode.app"
    }
}

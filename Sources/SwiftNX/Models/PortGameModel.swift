import Foundation
import SwiftNXKit

struct PortIssue: Identifiable {
    enum Severity: String {
        case info
        case warning
        case error
    }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
}

struct BuildPlan {
    let repository: URL
    let python: URL
    let script: URL
    let stagingFolder: URL
    let base: URL
    let update: URL?
    let dlc: [URL]
    let keys: URL
    let outputApp: URL
    let gameName: String
    let appName: String
    let titleID: TitleID?
    let version: String?
    let profile: GameProfile?
    let language: String
    let signIdentity: String
    let xcodePath: String

    var arguments: [String] {
        var args: [String] = [
            script.path,
            stagingFolder.path,
            "-k", keys.path,
            "--platform", "mac-app",
            "--progress", "json",
            "-l", language,
            "-o", outputApp.path,
            "--app-name", appName,
        ]
        if !signIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--mac-sign", signIdentity])
        }
        return args
    }

    var commandPreview: String {
        let command = ([python.path] + arguments)
            .map(StreamingProcess.shellQuote)
            .joined(separator: " ")
        return "cd \(StreamingProcess.shellQuote(repository.path))\n\(command)"
    }

    var estimatedDiskHint: String {
        "The first build can take 30–60 minutes and needs about twice the game size plus 10 GB."
    }
}

@MainActor
final class PortGameModel: ObservableObject {
    @Published var step: Int = 0
    @Published var baseURL: URL?
    @Published var updateURL: URL?
    @Published var dlcURLs: [URL] = []
    @Published private(set) var base: InspectedPackage?
    @Published private(set) var update: InspectedPackage?
    @Published var gameName: String = ""
    @Published var appName: String = ""
    @Published var language: String = "en-US"
    @Published var workingRoot: String = AppPaths.defaultWorkingRoot.path
    @Published var outputDirectory: String = AppPaths.defaultOutputDirectory.path
    @Published var keysPath: String = ""
    @Published var errorMessage: String?
    @Published private(set) var isPreparing = false
    @Published var profiles: [GameProfile] = []

    private var nameWasEdited = false
    private var appNameWasEdited = false

    var selectedLanguage: GameLanguage {
        GameLanguage.supported.first { $0.code == language } ?? GameLanguage.supported[0]
    }

    var baseTitleID: TitleID? {
        base?.titleID?.baseID ?? update?.titleID?.baseID
    }

    var matchedProfile: GameProfile? {
        guard let baseTitleID else { return nil }
        return profiles.first { $0.titleID == baseTitleID }
    }

    var resolvedGameName: String {
        let trimmed = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return matchedProfile?.name ?? base?.displayName ?? "Untitled Game"
    }

    var resolvedAppName: String {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? resolvedGameName : trimmed
    }

    var displayVersion: String? {
        if let updateVersion = update?.version {
            if let build = matchedProfile?.build(forNumericVersion: updateVersion) {
                return build.displayVersion
            }
            return "v\(updateVersion)"
        }
        if let baseVersion = base?.version {
            if let build = matchedProfile?.build(forNumericVersion: baseVersion) {
                return build.displayVersion
            }
            return "v\(baseVersion)"
        }
        return matchedProfile?.defaultDisplayVersion
    }

    var profileSupportText: String {
        guard let profile = matchedProfile else {
            return "No checked-in profile"
        }
        let selectedVersion = update?.version ?? base?.version
        if let selectedVersion,
           profile.build(forNumericVersion: selectedVersion) == nil {
            return "Profile found — selected version not listed"
        }
        return "Supported game"
    }

    var profileSupportDetail: String {
        guard let profile = matchedProfile else {
            return "nxnative will survey the game and build a provisional profile. Results vary; a checked-in profile is more reliable."
        }
        let selectedVersion = update?.version ?? base?.version
        if let selectedVersion, profile.build(forNumericVersion: selectedVersion) == nil {
            return "The profile supports \(profile.supportedVersionsText). Version v\(selectedVersion) is not registered; nxnative can derive a profile from your files, but exact support is not guaranteed."
        }
        return "\(profile.name) — supported versions: \(profile.supportedVersionsText)."
    }

    func applyDefaults(settings: AppSettings) {
        if workingRoot.isEmpty { workingRoot = settings.workingRoot }
        if outputDirectory.isEmpty { outputDirectory = settings.outputDirectory }
        if keysPath.isEmpty { keysPath = settings.keysPath }
        if language.isEmpty { language = settings.language }
        if !settings.keysPath.isEmpty, keysPath.isEmpty { keysPath = settings.keysPath }
    }

    func setBase(_ url: URL) {
        let inspected = PackageInspector.inspect(url: url)
        baseURL = url
        base = inspected
        errorMessage = nil
        if !nameWasEdited {
            let profile = profile(for: inspected.titleID)
            gameName = profile?.name ?? inspected.displayName
        }
        if !appNameWasEdited {
            appName = gameName
        }
        revalidateUpdate()
    }

    func clearBase() {
        baseURL = nil
        base = nil
        errorMessage = nil
    }

    func setUpdate(_ url: URL?) {
        guard let url else {
            updateURL = nil
            update = nil
            return
        }
        let inspected = PackageInspector.inspect(url: url)
        updateURL = url
        update = inspected
        revalidateUpdate()
    }

    func addDLC(_ urls: [URL]) {
        for url in urls where !dlcURLs.contains(url) {
            dlcURLs.append(url)
        }
    }

    func removeDLC(_ url: URL) {
        dlcURLs.removeAll { $0 == url }
    }

    func markGameNameEdited() {
        nameWasEdited = true
    }

    func markAppNameEdited() {
        appNameWasEdited = true
    }

    func reset() {
        step = 0
        baseURL = nil
        updateURL = nil
        dlcURLs = []
        base = nil
        update = nil
        gameName = ""
        appName = ""
        errorMessage = nil
        nameWasEdited = false
        appNameWasEdited = false
    }

    func issues(settings: AppSettings) -> [PortIssue] {
        var issues: [PortIssue] = []
        if baseURL == nil {
            issues.append(.init(
                severity: .error,
                title: "Choose a base game",
                detail: "Select the base game dump (NSP, XCI, NSZ or XCZ)."
            ))
        }
        if let base, base.titleID?.isUpdate == true {
            issues.append(.init(
                severity: .error,
                title: "This file looks like an update",
                detail: "The title ID ends in 800. Choose the base game here and put this file in the update slot."
            ))
        }
        if let baseID = base?.titleID?.baseID, let updateID = update?.titleID?.baseID, baseID != updateID {
            issues.append(.init(
                severity: .error,
                title: "Base game and update do not match",
                detail: "The files point to \(baseID.hex) and \(updateID.hex). Use a base game and update from the same release."
            ))
        }
        let keys = settings.keysURL
        if keys == nil || !FileManager.default.fileExists(atPath: keys!.path) {
            issues.append(.init(
                severity: .error,
                title: "prod.keys is missing",
                detail: "Choose your own prod.keys in Port settings or in Environment."
            ))
        }
        if !FileManager.default.fileExists(atPath: settings.repositoryURL.appendingPathComponent("scripts/build_ipa_from_nsp.py").path) {
            issues.append(.init(
                severity: .error,
                title: "nxnative is not ready",
                detail: "Clone or select the nxnative checkout in Environment."
            ))
        }
        if !FileManager.default.isExecutableFile(atPath: AppPaths.pythonExecutable.path) {
            issues.append(.init(
                severity: .error,
                title: "Python environment is missing",
                detail: "Create SwiftNX's isolated Python environment in Environment."
            ))
        }
        if resolvedAppName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.init(severity: .error, title: "App name is empty", detail: "Enter a name for the Mac app."))
        }
        if let base, base.titleID == nil {
            issues.append(.init(
                severity: .warning,
                title: "Title ID not detected",
                detail: "nxnative will read it from the game data while building. The profile lookup may be unavailable."
            ))
        }
        if matchedProfile == nil {
            issues.append(.init(
                severity: .warning,
                title: "No checked-in game profile",
                detail: profileSupportDetail
            ))
        } else if let profile = matchedProfile {
            let selectedVersion = update?.version ?? base?.version
            if let selectedVersion, profile.build(forNumericVersion: selectedVersion) == nil {
                issues.append(.init(
                    severity: .warning,
                    title: "Selected version is not in the profile",
                    detail: profileSupportDetail
                ))
            }
        }
        if let update, update.titleID != nil, !update.titleID!.isUpdate {
            issues.append(.init(
                severity: .warning,
                title: "The update file does not look like an update",
                detail: "Its title ID does not end in 800. Double-check that you picked the update, not another base game."
            ))
        }
        if let base, base.kind.isCompressed {
            issues.append(.init(
                severity: .info,
                title: "Compressed package",
                detail: "nxnative will decompress the \(base.kind.displayName) with nsz before building. The first build takes longer."
            ))
        }
        return issues
    }

    func preparePlan(settings: AppSettings) throws -> BuildPlan {
        let issues = issues(settings: settings)
        if let error = issues.first(where: { $0.severity == .error }) {
            throw PortError.invalidPlan("\(error.title). \(error.detail)")
        }
        guard let baseURL else {
            throw PortError.invalidPlan("Choose a base game first.")
        }
        guard let keys = settings.keysURL,
              FileManager.default.fileExists(atPath: keys.path)
        else {
            throw PortError.invalidPlan("prod.keys is missing.")
        }
        let repo = settings.repositoryURL
        let script = repo.appendingPathComponent("scripts/build_ipa_from_nsp.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw PortError.invalidPlan("The nxnative checkout is incomplete.")
        }
        guard FileManager.default.isExecutableFile(atPath: AppPaths.pythonExecutable.path) else {
            throw PortError.invalidPlan("SwiftNX's Python environment is missing.")
        }

        let fm = FileManager.default
        let workingRootURL = URL(fileURLWithPath: AppPaths.expanded(workingRoot), isDirectory: true)
        let outputURL = URL(fileURLWithPath: AppPaths.expanded(outputDirectory), isDirectory: true)
        try fm.createDirectory(at: workingRootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        let identifier = baseTitleID?.hex ?? ""
        var folderName = AppPaths.sanitizeFilename(resolvedGameName)
        if !identifier.isEmpty { folderName += " [\(identifier)]" }
        let staging = workingRootURL.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        var packages = [baseURL]
        if let updateURL { packages.append(updateURL) }
        packages.append(contentsOf: dlcURLs)
        try link(packages: packages, into: staging)

        var appFileName = AppPaths.sanitizeFilename(resolvedAppName)
        if appFileName.lowercased().hasSuffix(".app") {
            appFileName = String(appFileName.dropLast(4))
        }
        let outputApp = outputURL.appendingPathComponent(appFileName + ".app", isDirectory: true)

        return BuildPlan(
            repository: repo,
            python: AppPaths.pythonExecutable,
            script: script,
            stagingFolder: staging,
            base: baseURL,
            update: updateURL,
            dlc: dlcURLs,
            keys: keys,
            outputApp: outputApp,
            gameName: resolvedGameName,
            appName: resolvedAppName,
            titleID: baseTitleID,
            version: displayVersion,
            profile: matchedProfile,
            language: selectedLanguage.code,
            signIdentity: settings.signIdentity,
            xcodePath: settings.xcodePath
        )
    }

    private func link(packages: [URL], into staging: URL) throws {
        let fm = FileManager.default
        let stagingPath = staging.standardizedFileURL.path
        if let existing = try? fm.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) {
            for item in existing {
                guard PackageFileKind(url: item) != nil else { continue }
                let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    try fm.removeItem(at: item)
                }
            }
        }

        for package in packages {
            if package.deletingLastPathComponent().standardizedFileURL.path == stagingPath {
                continue
            }
            let destination = staging.appendingPathComponent(package.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                let destinationPath = destination.resolvingSymlinksInPath().path
                if destinationPath == package.resolvingSymlinksInPath().path { continue }
                throw PortError.invalidPlan(
                    "The working folder already contains a real file named \(package.lastPathComponent). Choose another working folder or remove that file."
                )
            }
            try fm.createSymbolicLink(at: destination, withDestinationURL: package)
        }
    }

    private func profile(for titleID: TitleID?) -> GameProfile? {
        guard let titleID else { return nil }
        return profiles.first { $0.titleID == titleID.baseID }
    }

    private func revalidateUpdate() {
        guard let update, let baseID = base?.titleID?.baseID else { return }
        if let updateID = update.titleID?.baseID, updateID != baseID {
            errorMessage = "The selected update belongs to \(updateID.hex), not \(baseID.hex)."
        } else {
            errorMessage = nil
        }
    }
}

enum PortError: LocalizedError {
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlan(let message): return message
        }
    }
}

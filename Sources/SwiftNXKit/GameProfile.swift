import Foundation

public struct GameBuild: Hashable, Codable, Sendable {
    /// The package key nxnative uses, for example `v0` or `v327680`.
    public let packageKey: String
    /// The human-facing display version, for example `1.2.1`.
    public let displayVersion: String
    /// Module name to build ID, as listed in the profile.
    public let moduleBuilds: [String: String]

    public init(packageKey: String, displayVersion: String, moduleBuilds: [String: String]) {
        self.packageKey = packageKey
        self.displayVersion = displayVersion
        self.moduleBuilds = moduleBuilds
    }

    public var numericVersion: UInt64? {
        guard packageKey.lowercased().hasPrefix("v") else { return nil }
        return UInt64(packageKey.dropFirst())
    }
}

public struct GameProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: String { titleID.hex }
    public let titleID: TitleID
    public let name: String
    public let defaultPackage: String?
    public let builds: [GameBuild]
    public let shaderVersions: [String]
    public let appCategory: String?
    public let profileURL: URL

    public init(
        titleID: TitleID,
        name: String,
        defaultPackage: String?,
        builds: [GameBuild],
        shaderVersions: [String],
        appCategory: String?,
        profileURL: URL
    ) {
        self.titleID = titleID
        self.name = name
        self.defaultPackage = defaultPackage
        self.builds = builds
        self.shaderVersions = shaderVersions
        self.appCategory = appCategory
        self.profileURL = profileURL
    }

    public var defaultBuild: GameBuild? {
        if let defaultPackage, let match = builds.first(where: { $0.packageKey == defaultPackage }) {
            return match
        }
        return builds.last
    }

    public var defaultDisplayVersion: String? { defaultBuild?.displayVersion }

    public func build(forPackageKey key: String) -> GameBuild? {
        builds.first { $0.packageKey.caseInsensitiveCompare(key) == .orderedSame }
    }

    public func build(forNumericVersion version: UInt64) -> GameBuild? {
        builds.first { $0.numericVersion == version }
    }

    public var supportedVersionsText: String {
        builds.map(\.displayVersion).joined(separator: ", ")
    }
}

public struct GameProfileStore: Sendable {
    public let profiles: [GameProfile]
    public let repositoryURL: URL

    public init(repositoryURL: URL) throws {
        self.repositoryURL = repositoryURL
        let gamesURL = repositoryURL.appendingPathComponent("dm/games", isDirectory: true)
        guard FileManager.default.fileExists(atPath: gamesURL.path) else {
            throw GameProfileError.missingProfilesFolder(gamesURL)
        }
        let folders = try FileManager.default.contentsOfDirectory(
            at: gamesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var loaded: [GameProfile] = []
        for folder in folders {
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let tsv = folder.appendingPathComponent("game.tsv")
            guard FileManager.default.fileExists(atPath: tsv.path) else { continue }
            if let profile = try? Self.parseProfile(at: tsv, folder: folder) {
                loaded.append(profile)
            }
        }
        self.profiles = loaded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func profile(for titleID: TitleID?) -> GameProfile? {
        guard let titleID else { return nil }
        return profiles.first { $0.titleID == titleID || $0.titleID == titleID.baseID }
    }

    public func profile(forBaseID baseID: TitleID) -> GameProfile? {
        profiles.first { $0.titleID == baseID }
    }

    static func parseProfile(at url: URL, folder: URL) throws -> GameProfile {
        let text = try String(contentsOf: url, encoding: .utf8)
        var titleID: TitleID?
        var name: String?
        var package: String?
        var builds: [GameBuild] = []
        var shaderVersions: [String] = []
        var appCategory: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let columns = line.components(separatedBy: "\t")
            guard let key = columns.first?.trimmingCharacters(in: .whitespaces) else { continue }
            func value(_ index: Int) -> String? {
                index < columns.count ? columns[index].trimmingCharacters(in: .whitespaces) : nil
            }

            switch key {
            case "title_id":
                if let raw = value(1) { titleID = TitleID(hex: raw) }
            case "name":
                name = value(1)
            case "package":
                package = value(1)
            case "build":
                guard let packageKey = value(1),
                      let display = value(2),
                      !packageKey.isEmpty, !display.isEmpty
                else { continue }
                var modules: [String: String] = [:]
                if let specs = value(3) {
                    for spec in specs.split(separator: " ") {
                        let parts = spec.split(separator: "=", maxSplits: 1)
                        if parts.count == 2 {
                            modules[String(parts[0])] = String(parts[1])
                        }
                    }
                }
                builds.append(GameBuild(
                    packageKey: packageKey,
                    displayVersion: display,
                    moduleBuilds: modules
                ))
            case "shader_versions":
                if let raw = value(1) {
                    shaderVersions = raw.split(separator: " ").map(String.init)
                }
            case "app_category":
                appCategory = value(1)
            default:
                break
            }
        }

        guard let titleID else { throw GameProfileError.missingTitleID(url) }
        let fallbackName = folder.lastPathComponent
        return GameProfile(
            titleID: titleID,
            name: (name?.isEmpty == false ? name! : fallbackName),
            defaultPackage: package,
            builds: builds,
            shaderVersions: shaderVersions,
            appCategory: appCategory,
            profileURL: folder
        )
    }
}

public enum GameProfileError: LocalizedError {
    case missingProfilesFolder(URL)
    case missingTitleID(URL)

    public var errorDescription: String? {
        switch self {
        case .missingProfilesFolder(let url):
            return "No dm/games folder in \(url.path). Is this the nxnative checkout?"
        case .missingTitleID(let url):
            return "The game profile \(url.lastPathComponent) has no title_id row."
        }
    }
}

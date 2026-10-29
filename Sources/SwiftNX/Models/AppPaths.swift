import Foundation

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftNX", isDirectory: true)
    }

    static var logsDirectory: URL {
        supportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    static var venvDirectory: URL {
        supportDirectory.appendingPathComponent("venv", isDirectory: true)
    }

    static var pythonExecutable: URL {
        venvDirectory.appendingPathComponent("bin/python3")
    }

    static var keysDirectory: URL {
        supportDirectory.appendingPathComponent("keys", isDirectory: true)
    }

    static var defaultKeysFile: URL {
        keysDirectory.appendingPathComponent("prod.keys")
    }

    static var libraryFile: URL {
        supportDirectory.appendingPathComponent("library.json")
    }

    static var defaultWorkingRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Games/SwiftNX", isDirectory: true)
    }

    static var defaultOutputDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/SwiftNX", isDirectory: true)
    }

    static var defaultRepository: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("nxnative", isDirectory: true)
    }

    static func prepare() {
        for url in [supportDirectory, logsDirectory, keysDirectory] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: keysDirectory.path
        )
    }

    static func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: expanded(path), isDirectory: false)
    }

    static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func abbreviate(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    static func sanitizeFilename(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: " - ")
            .replacingOccurrences(of: ":", with: " - ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }
        if name.isEmpty { name = "Game" }
        return name
    }

    static func newLogFile(named prefix: String) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return logsDirectory.appendingPathComponent("\(prefix)-\(stamp).log")
    }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
    let date: Date = Date()
}

import AppKit
import Foundation

enum ToolLocator {
    static func searchPaths(venv: URL? = AppPaths.venvDirectory) -> [String] {
        var paths: [String] = []
        if let venv {
            paths.append(venv.appendingPathComponent("bin").path)
        }
        paths.append(contentsOf: [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.dotnet",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/share/dotnet",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ])
        return paths
    }

    static func find(_ name: String, venv: URL? = AppPaths.venvDirectory) -> String? {
        for directory in searchPaths(venv: venv) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    static func brewPath() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return find("brew")
    }

    static func developerDirectory(xcodePath: String) -> String? {
        guard !xcodePath.isEmpty else { return nil }
        let app = AppPaths.url(xcodePath)
        let developer = app.appendingPathComponent("Contents/Developer").path
        return FileManager.default.fileExists(atPath: developer) ? developer : nil
    }

    static func baseEnvironment(xcodePath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPaths().joined(separator: ":")
        environment["HOME"] = NSHomeDirectory()
        environment["USER"] = NSUserName()
        environment["LOGNAME"] = environment["LOGNAME"] ?? NSUserName()
        environment["SHELL"] = environment["SHELL"] ?? "/bin/zsh"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["NSUnbufferedIO"] = "YES"
        if let developer = developerDirectory(xcodePath: xcodePath) {
            environment["DEVELOPER_DIR"] = developer
        }
        return environment
    }

    static func runVersionCommand(path: String, arguments: [String], xcodePath: String) async -> (status: Int32, output: String) {
        do {
            let result = try await CommandRunner.run(
                path: path,
                arguments: arguments,
                environment: baseEnvironment(xcodePath: xcodePath)
            )
            return (result.status, result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

enum AppActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openApp(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Opens a Terminal window with a prepared command. Used for steps that
    /// legitimately need the user's password (Homebrew/.NET installers and the
    /// Xcode license); SwiftNX never asks for or handles the password itself.
    static func runInTerminal(command: String, title: String) {
        let script = """
        #!/bin/bash
        export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
        echo \(StreamingProcess.shellQuote(title))
        echo
        \(command)
        status=$?
        echo
        if [ $status -eq 0 ]; then
            echo "Done. You can close this window."
        else
            echo "Finished with status $status."
        fi
        echo
        read -n 1 -s -r -p "Press any key to close this window…"
        echo
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftNX-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}

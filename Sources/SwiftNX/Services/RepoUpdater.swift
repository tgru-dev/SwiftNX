import Foundation

struct RepoInfo {
    let path: String
    let branch: String
    let commit: String
    let subject: String
    let commitDate: String
    let dirty: Bool
    let remote: String?
    let ahead: Int
    let behind: Int
    let isGit: Bool
}

@MainActor
final class RepoUpdater: ObservableObject {
    @Published private(set) var info: RepoInfo?
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var repositoryExists: Bool {
        FileManager.default.fileExists(atPath: settings.repositoryURL.path)
    }

    func refresh() {
        guard !isWorking else { return }
        isWorking = true
        Task { await load(showSpinner: true) }
    }

    func checkForUpdates() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            guard let git = ToolLocator.find("git") else {
                message = "git is not installed."
                isWorking = false
                return
            }
            let result = await run(git: git, arguments: ["fetch", "--quiet"])
            if !result.succeeded {
                message = "Fetch failed: \(result.combinedOutput)"
                isWorking = false
                return
            }
            await load(showSpinner: false)
            if let behind = info?.behind, behind > 0 {
                message = "\(behind) new commit\(behind == 1 ? "" : "s") available upstream."
            } else {
                message = "nxnative is up to date."
            }
            isWorking = false
            lastChecked = Date()
        }
    }

    func update() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            guard let git = ToolLocator.find("git") else {
                message = "git is not installed."
                isWorking = false
                return
            }
            let pull = await run(git: git, arguments: ["pull", "--ff-only"])
            if pull.succeeded {
                await load(showSpinner: false)
                message = "nxnative was updated. SwiftNX's own settings were left untouched."
            } else {
                message = "Update failed: \(pull.combinedOutput)"
            }
            isWorking = false
            lastChecked = Date()
        }
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { isWorking = true }
        defer { isWorking = false }
        lastChecked = Date()
        let repo = settings.repositoryURL
        guard FileManager.default.fileExists(atPath: repo.path) else {
            info = nil
            message = "nxnative is not cloned yet."
            return
        }
        guard let git = ToolLocator.find("git") else {
            info = nil
            message = "git is not installed."
            return
        }
        let probe = await run(git: git, arguments: ["rev-parse", "--is-inside-work-tree"])
        guard probe.succeeded, probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            info = nil
            message = "This folder is not a Git checkout."
            return
        }
        async let branchResult = run(git: git, arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
        async let commitResult = run(git: git, arguments: ["rev-parse", "--short", "HEAD"])
        async let logResult = run(git: git, arguments: ["log", "-1", "--format=%cs%n%s"])
        async let statusResult = run(git: git, arguments: ["status", "--porcelain"])
        async let remoteResult = run(git: git, arguments: ["remote", "get-url", "origin"])
        async let countsResult = run(git: git, arguments: ["rev-list", "--left-right", "--count", "@{u}...HEAD"])

        let branch = await branchResult
        let commit = await commitResult
        let log = await logResult
        let status = await statusResult
        let remote = await remoteResult
        let counts = await countsResult

        let logLines = log.stdout.components(separatedBy: .newlines)
        var ahead = 0
        var behind = 0
        if counts.succeeded {
            let fields = counts.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " })
            if fields.count >= 2 {
                behind = Int(fields[0]) ?? 0
                ahead = Int(fields[1]) ?? 0
            }
        }
        info = RepoInfo(
            path: repo.path,
            branch: branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            commit: commit.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: logLines.count > 1 ? logLines[1] : "",
            commitDate: logLines.first ?? "",
            dirty: !status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            remote: remote.succeeded ? remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            ahead: ahead,
            behind: behind,
            isGit: true
        )
        if message == nil || message == "nxnative is not cloned yet." {
            message = "Checked \(Date().formatted(date: .omitted, time: .shortened))."
        }
    }

    private func run(git: String, arguments: [String]) async -> CommandResult {
        do {
            return try await CommandRunner.run(
                path: git,
                arguments: arguments,
                environment: ToolLocator.baseEnvironment(xcodePath: settings.xcodePath),
                currentDirectory: settings.repositoryURL
            )
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
    }
}

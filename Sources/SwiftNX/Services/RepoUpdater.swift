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
    @Published private(set) var isSyncingOnLaunch = false
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?

    var onRepositoryUpdated: (() -> Void)?

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

    /// Clones nxnative on first launch and fast-forwards an existing checkout
    /// before the app is used. Local changes are never discarded.
    func syncOnLaunch() {
        guard !isWorking else { return }
        isWorking = true
        isSyncingOnLaunch = true
        Task {
            await syncLatest()
            isWorking = false
            isSyncingOnLaunch = false
            lastChecked = Date()
            onRepositoryUpdated?()
        }
    }

    private func syncLatest() async {
        guard let git = ToolLocator.find("git") else {
            message = "Automatic nxnative update skipped: git is not installed."
            return
        }

        let repo = settings.repositoryURL
        let fileManager = FileManager.default
        let repoExists = fileManager.fileExists(atPath: repo.path)
        let repoIsEmpty = repoExists
            && ((try? fileManager.contentsOfDirectory(atPath: repo.path)) ?? []).isEmpty

        if !repoExists || repoIsEmpty {
            try? fileManager.createDirectory(
                at: repo.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let parent = repo.deletingLastPathComponent()
            let clone = await run(
                git: git,
                arguments: [
                    "clone", "--quiet",
                    "https://github.com/seedds/nxnative.git",
                    repo.path,
                ],
                currentDirectory: parent
            )
            if clone.succeeded {
                await load(showSpinner: false)
                message = "Downloaded the latest nxnative checkout."
            } else {
                info = nil
                message = "Could not download nxnative: \(outputSummary(clone))"
            }
            return
        }

        let probe = await run(git: git, arguments: ["rev-parse", "--is-inside-work-tree"])
        guard probe.succeeded,
              probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            message = "The nxnative folder is not a Git checkout; automatic update skipped."
            return
        }

        let fetch = await run(git: git, arguments: ["fetch", "--quiet", "--prune"])
        await load(showSpinner: false)
        guard fetch.succeeded else {
            message = "Could not check nxnative for updates: \(outputSummary(fetch))"
            return
        }
        guard let info else { return }

        if info.dirty {
            message = info.behind > 0
                ? "\(info.behind) nxnative update\(info.behind == 1 ? "" : "s") available, but the checkout has local changes. Automatic update skipped."
                : "nxnative is up to date. Local changes were left untouched."
            return
        }

        guard info.behind > 0 else {
            message = "nxnative is up to date at \(info.commit)."
            return
        }

        let pull = await run(git: git, arguments: ["pull", "--ff-only", "--quiet"])
        if pull.succeeded {
            await load(showSpinner: false)
            message = "Updated nxnative to the latest version."
        } else {
            message = "Could not fast-forward nxnative: \(outputSummary(pull))"
        }
    }

    private func outputSummary(_ result: CommandResult) -> String {
        let text = result.combinedOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(3)
            .joined(separator: " ")
        if text.isEmpty {
            return result.status == 0 ? "done" : "git exited with status \(result.status)."
        }
        return String(text.prefix(400))
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
        defer { if showSpinner { isWorking = false } }
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

    private func run(
        git: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) async -> CommandResult {
        do {
            return try await CommandRunner.run(
                path: git,
                arguments: arguments,
                environment: ToolLocator.baseEnvironment(xcodePath: settings.xcodePath),
                currentDirectory: currentDirectory ?? settings.repositoryURL
            )
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
    }
}

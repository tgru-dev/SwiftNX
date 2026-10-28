import Foundation
import SwiftNXKit

enum BuildState: String {
    case idle
    case preparing
    case running
    case cancelling
    case succeeded
    case failed
    case cancelled

    var isActive: Bool {
        self == .preparing || self == .running || self == .cancelling
    }
}

enum BuildStageStatus {
    case running
    case succeeded
    case failed
}

struct BuildStage: Identifiable {
    let id: Int
    var k: Int
    var n: Int
    var name: String
    var step: String
    var done: Int?
    var total: Int?
    var unit: String?
    var estimated: Bool = false
    var note: String = ""
    var rawFraction: Double?
    var eta: Double?
    var elapsed: Double?
    var status: BuildStageStatus = .running
    var summary: String?

    var fraction: Double {
        if status == .succeeded { return 1 }
        if let rawFraction { return min(max(rawFraction, 0), 1) }
        if let done, let total, total > 0 { return min(Double(done) / Double(total), 0.99) }
        return 0
    }

    var countText: String? {
        guard done != nil || total != nil else { return nil }
        let doneText = BuildFormatting.count(done, unit: unit, estimated: estimated)
        if let total {
            return "\(doneText) / \(BuildFormatting.count(total, unit: unit, estimated: estimated))"
        }
        return doneText
    }
}

@MainActor
final class BuildController: ObservableObject {
    @Published private(set) var state: BuildState = .idle
    @Published private(set) var stages: [BuildStage] = []
    @Published private(set) var totalStages = 0
    @Published private(set) var logLines: [LogLine] = []
    @Published private(set) var latestMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var command: String = ""
    @Published private(set) var logFileURL: URL?
    @Published private(set) var outputApp: URL?
    @Published private(set) var finishedEntry: LibraryEntry?
    @Published private(set) var plan: BuildPlan?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    @Published private(set) var isCancelling = false

    private var process: StreamingProcess?
    private var ticker: Task<Void, Never>?
    private var logHandle: FileHandle?
    private var activityToken: NSObjectProtocol?
    private var cancelledByUser = false
    private var recentErrors: [String] = []

    var isRunning: Bool { state.isActive }
    var currentStage: BuildStage? {
        stages.last { $0.status == .running } ?? stages.last
    }

    var overallFraction: Double {
        guard totalStages > 0 else { return state == .succeeded ? 1 : 0 }
        let completed = stages.filter { $0.status == .succeeded || $0.status == .failed }.count
        let running = stages.last { $0.status == .running }?.fraction ?? 0
        return min(1, max(0, (Double(completed) + running) / Double(max(totalStages, stages.count))))
    }

    var overallETA: TimeInterval? {
        guard state == .running, overallFraction > 0.02, elapsed > 2 else { return nil }
        return max(0, elapsed / overallFraction - elapsed)
    }

    var statusTitle: String {
        switch state {
        case .idle: return "Ready"
        case .preparing: return "Preparing build"
        case .running: return "Building"
        case .cancelling: return "Stopping…"
        case .succeeded: return "Build complete"
        case .failed: return "Build failed"
        case .cancelled: return "Build cancelled"
        }
    }

    var statusDetail: String {
        switch state {
        case .idle: return "Choose a game and start a port."
        case .preparing: return "Checking paths and starting the nxnative pipeline…"
        case .running: return currentStage.map { "Stage \($0.k) of \($0.n): \($0.name)" } ?? "Starting nxnative…"
        case .cancelling: return "Waiting for the build process to exit."
        case .succeeded: return finishedEntry.map { "\($0.title) is ready in your library." } ?? "The app is ready."
        case .failed: return errorMessage ?? "nxnative stopped. See the log for details."
        case .cancelled: return "The build was stopped. You can start again at any time."
        }
    }

    func start(
        plan: BuildPlan,
        settings: AppSettings,
        onSuccess: @escaping (LibraryEntry) -> Void
    ) {
        guard !isRunning else { return }
        reset()
        self.plan = plan
        command = plan.commandPreview
        startedAt = Date()
        state = .preparing
        errorMessage = nil
        isCancelling = false
        cancelledByUser = false
        recentErrors = []
        beginActivity()

        let logURL = AppPaths.newLogFile(named: "build")
        logFileURL = logURL
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
        writeToLog("SwiftNX build log — \(Date())")
        writeToLog(command)
        writeToLog("")

        startTicker()
        state = .running

        let environment = ToolLocator.baseEnvironment(xcodePath: plan.xcodePath)
        let process = StreamingProcess()
        self.process = process
        process.onStdout = { [weak self] line in
            self?.handleStdout(line)
        }
        process.onStderr = { [weak self] line in
            self?.handleStderr(line)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await process.run(
                    executable: plan.python,
                    arguments: plan.arguments,
                    environment: environment,
                    currentDirectory: plan.repository
                )
                self.finish(status: status, plan: plan, onSuccess: onSuccess)
            } catch {
                self.failLaunch(error)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelledByUser = true
        isCancelling = true
        state = .cancelling
        latestMessage = "Stopping the build…"
        process?.terminate()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.state == .cancelling else { return }
            self.process?.forceKill()
        }
    }

    func reset() {
        guard !isRunning else { return }
        ticker?.cancel()
        ticker = nil
        endActivity()
        closeLog()
        state = .idle
        stages = []
        totalStages = 0
        logLines = []
        latestMessage = nil
        errorMessage = nil
        command = ""
        logFileURL = nil
        outputApp = nil
        finishedEntry = nil
        plan = nil
        elapsed = 0
        startedAt = nil
        finishedAt = nil
        isCancelling = false
        cancelledByUser = false
        recentErrors = []
    }

    private func handleStdout(_ line: String) {
        appendLog(line, isError: false)
        if let event = BuildEventParser.parse(line: line) {
            handle(event)
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            latestMessage = line
        }
    }

    private func handleStderr(_ line: String) {
        appendLog(line, isError: true)
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        recentErrors.append(line)
        if recentErrors.count > 30 { recentErrors.removeFirst(recentErrors.count - 30) }
        latestMessage = line
    }

    private func handle(_ event: BuildEvent) {
        switch event.kind {
        case .stage:
            guard let k = event.k, let name = event.name else { return }
            if let n = event.n { totalStages = max(totalStages, n) }
            if let index = stages.firstIndex(where: { $0.k == k }) {
                var copy = stages
                copy[index].name = name
                copy[index].step = event.step ?? ""
                copy[index].status = .running
                stages = copy
            } else {
                stages.append(BuildStage(
                    id: k,
                    k: k,
                    n: event.n ?? max(totalStages, k),
                    name: name,
                    step: event.step ?? ""
                ))
                stages.sort { $0.k < $1.k }
            }
            latestMessage = "Stage \(k): \(name)"
            if state == .preparing { state = .running }

        case .step:
            guard let k = event.k, let index = stages.firstIndex(where: { $0.k == k }) else { return }
            var copy = stages
            copy[index].step = event.step ?? ""
            copy[index].done = nil
            copy[index].total = nil
            copy[index].rawFraction = nil
            stages = copy
            latestMessage = "\(copy[index].name) · \(event.step ?? "")"

        case .progress:
            guard let k = event.k, let index = stages.firstIndex(where: { $0.k == k }) else { return }
            var copy = stages
            copy[index].step = event.step ?? copy[index].step
            copy[index].done = event.done ?? copy[index].done
            copy[index].total = event.total ?? copy[index].total
            copy[index].unit = event.unit ?? copy[index].unit
            copy[index].estimated = event.estimated ?? copy[index].estimated
            copy[index].note = event.note ?? copy[index].note
            copy[index].rawFraction = event.fraction ?? copy[index].rawFraction
            copy[index].eta = event.eta ?? copy[index].eta
            copy[index].elapsed = event.elapsed ?? copy[index].elapsed
            stages = copy

        case .stageEnd:
            guard let k = event.k, let index = stages.firstIndex(where: { $0.k == k }) else { return }
            var copy = stages
            copy[index].status = event.ok == false ? .failed : .succeeded
            copy[index].summary = event.summary
            copy[index].elapsed = event.elapsed ?? copy[index].elapsed
            copy[index].rawFraction = event.ok == false ? copy[index].rawFraction : 1
            stages = copy
            if event.ok == false {
                errorMessage = "Stage “\(copy[index].name)” failed. \(event.summary ?? "")"
            }

        case .say:
            guard let message = event.message else { return }
            latestMessage = message
            if message.contains("[RED]") {
                recentErrors.append(message)
                errorMessage = message
            }

        case .unknown:
            break
        }
    }

    private func finish(status: Int32, plan: BuildPlan, onSuccess: (LibraryEntry) -> Void) {
        ticker?.cancel()
        ticker = nil
        endActivity()
        finishedAt = Date()
        isCancelling = false
        defer { closeLog() }

        if cancelledByUser || state == .cancelling {
            state = .cancelled
            latestMessage = "Build cancelled."
            writeToLog("Build cancelled by user.")
            return
        }

        guard status == 0 else {
            state = .failed
            let tail = recentErrors.suffix(6).joined(separator: "\n")
            if errorMessage == nil || errorMessage?.isEmpty == true {
                errorMessage = tail.isEmpty ? "nxnative exited with status \(status)." : tail
            }
            latestMessage = "nxnative exited with status \(status)."
            writeToLog("Build failed with exit status \(status).")
            return
        }

        if let failed = stages.first(where: { $0.status == .failed }) {
            state = .failed
            if errorMessage == nil || errorMessage?.isEmpty == true {
                errorMessage = "Stage “\(failed.name)” failed. \(failed.summary ?? "")"
            }
            latestMessage = errorMessage
            writeToLog("Build reported a failed stage.")
            return
        }

        var appURL: URL? = FileManager.default.fileExists(atPath: plan.outputApp.path) ? plan.outputApp : nil
        if appURL == nil,
           let contents = try? FileManager.default.contentsOfDirectory(
               at: plan.stagingFolder,
               includingPropertiesForKeys: [.contentModificationDateKey],
               options: [.skipsHiddenFiles]
           ) {
            appURL = contents
                .filter { $0.pathExtension.lowercased() == "app" }
                .sorted {
                    let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return lhs > rhs
                }
                .first
        }

        guard let appURL else {
            state = .failed
            errorMessage = "nxnative finished, but SwiftNX could not find the built .app bundle."
            latestMessage = errorMessage
            return
        }

        let metadata = AppMetadataReader.read(appURL)
        let titleID = metadata.titleID ?? plan.titleID
        let entry = LibraryEntry(
            title: metadata.name ?? plan.gameName,
            titleID: titleID?.hex,
            version: metadata.version ?? plan.version,
            path: appURL.path,
            profileName: plan.profile?.name,
            language: plan.language,
            bundleIdentifier: metadata.bundleIdentifier
        )
        outputApp = appURL
        finishedEntry = entry
        state = .succeeded
        errorMessage = nil
        latestMessage = "Build complete — \(appURL.lastPathComponent)"
        writeToLog("Build complete: \(appURL.path)")
        onSuccess(entry)
    }

    private func failLaunch(_ error: Error) {
        ticker?.cancel()
        ticker = nil
        endActivity()
        closeLog()
        state = .failed
        errorMessage = "Could not start nxnative: \(error.localizedDescription)"
        latestMessage = errorMessage
    }

    private func appendLog(_ line: String, isError: Bool) {
        writeToLog(line)
        guard !line.isEmpty else { return }
        logLines.append(LogLine(text: line, isError: isError))
        if logLines.count > 4_000 {
            logLines.removeFirst(logLines.count - 3_000)
        }
    }

    private func writeToLog(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? logHandle?.write(contentsOf: data)
    }

    private func closeLog() {
        try? logHandle?.close()
        logHandle = nil
    }

    private func tick() {
        guard let startedAt, state == .running || state == .preparing || state == .cancelling else { return }
        elapsed = Date().timeIntervalSince(startedAt)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func beginActivity() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "SwiftNX is building a game with nxnative"
        )
    }

    private func endActivity() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }
}

struct AppMetadata {
    let name: String?
    let version: String?
    let bundleIdentifier: String?
    let titleID: TitleID?
}

enum AppMetadataReader {
    static func read(_ appURL: URL) -> AppMetadata {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return AppMetadata(name: nil, version: nil, bundleIdentifier: nil, titleID: nil)
        }
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
        let version = plist["CFBundleShortVersionString"] as? String
        let bundleID = plist["CFBundleIdentifier"] as? String
        let titleText = (plist["DMTitleID"] as? String)
            ?? (plist["DMGameID"] as? String)
        var titleID = titleText.flatMap(TitleID.init(hex:))
        if titleID == nil, let number = (plist["DMTitleID"] as? NSNumber) ?? (plist["DMGameID"] as? NSNumber) {
            titleID = TitleID(value: number.uint64Value)
        }
        return AppMetadata(
            name: name,
            version: version,
            bundleIdentifier: bundleID,
            titleID: titleID
        )
    }
}

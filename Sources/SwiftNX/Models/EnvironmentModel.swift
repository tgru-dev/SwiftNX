import Foundation
import SwiftNXKit

enum CheckStatus: String {
    case ok
    case warning
    case missing
    case blocked

    var isProblem: Bool { self == .missing || self == .blocked }
}

enum CheckAction: String {
    case installHomebrew
    case installBrewTools
    case setupPython
    case installDotnet
    case installMetalToolchain
    case openXcode
    case acceptXcodeLicense
    case cloneRepository
    case chooseKeys
}

struct ToolCheck: Identifiable {
    enum Group: String, CaseIterable {
        case system = "System"
        case xcode = "Xcode & Metal"
        case tools = "Build tools"
        case python = "Python environment"
        case project = "nxnative"
        case files = "Game files & storage"
    }

    let id: String
    let group: Group
    let title: String
    var detail: String
    var status: CheckStatus
    var required: Bool = true
    var action: CheckAction?
    var actionLabel: String?
}

@MainActor
final class EnvironmentModel: ObservableObject {
    @Published private(set) var checks: [ToolCheck] = []
    @Published private(set) var profiles: [GameProfile] = []
    @Published private(set) var profileError: String?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published var externalMessage: String?

    let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var blockers: [ToolCheck] {
        checks.filter { $0.required && $0.status.isProblem }
    }

    var ready: Bool { blockers.isEmpty && !checks.isEmpty }

    var warningCount: Int {
        checks.filter { $0.status == .warning }.count
    }

    var summary: String {
        if isChecking { return "Checking this Mac…" }
        if checks.isEmpty { return "Not checked yet" }
        if !ready { return "Setup needed" }
        if warningCount > 0 { return "Ready, with notes" }
        return "Ready to build"
    }

    func check(id: String) -> ToolCheck? {
        checks.first { $0.id == id }
    }

    func refresh() {
        guard !isChecking else { return }
        isChecking = true
        Task { await performChecks() }
    }

    func clearMessage() { externalMessage = nil }

    private func performChecks() async {
        var results: [ToolCheck] = []
        let xcode = settings.xcodePath
        let developer = ToolLocator.developerDirectory(xcodePath: xcode)
        let venvPython = AppPaths.pythonExecutable

        // Apple silicon (sysctl lives in /usr/sbin; uname is the fallback)
        let arch = await ToolLocator.runVersionCommand(
            path: "/usr/sbin/sysctl",
            arguments: ["-n", "hw.optional.arm64"],
            xcodePath: xcode
        )
        var isArm = arch.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        if !isArm {
            let machine = await ToolLocator.runVersionCommand(
                path: "/usr/bin/uname",
                arguments: ["-m"],
                xcodePath: xcode
            )
            isArm = machine.output.trimmingCharacters(in: .whitespacesAndNewlines) == "arm64"
        }
        results.append(ToolCheck(
            id: "system.arm64",
            group: .system,
            title: "Apple silicon Mac",
            detail: isArm ? "Native arm64 host detected." : "nxnative requires an Apple silicon Mac (M1 or newer).",
            status: isArm ? .ok : .blocked
        ))

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osText = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let osSupported = os.majorVersion > 26 || (os.majorVersion == 26 && os.minorVersion >= 6)
        results.append(ToolCheck(
            id: "system.macos",
            group: .system,
            title: "macOS version",
            detail: osSupported
                ? "\(osText) — compatible with the current nxnative toolchain."
                : "\(osText) — the current nxnative recommends macOS 26.6 or later.",
            status: osSupported ? .ok : .warning,
            required: false
        ))

        // Xcode
        if developer != nil {
            let version = await ToolLocator.runVersionCommand(
                path: "/usr/bin/xcodebuild",
                arguments: ["-version"],
                xcodePath: xcode
            )
            let lower = version.output.lowercased()
            let selectedCLT = await ToolLocator.runVersionCommand(
                path: "/usr/bin/xcode-select",
                arguments: ["-p"],
                xcodePath: xcode
            ).output
            if lower.contains("license") {
                results.append(ToolCheck(
                    id: "xcode",
                    group: .xcode,
                    title: "Xcode",
                    detail: "Xcode is installed, but its license has not been accepted. Accept it once in Terminal:\n/usr/bin/sudo /usr/bin/xcodebuild -license accept",
                    status: .blocked,
                    action: .acceptXcodeLicense,
                    actionLabel: "Open Terminal"
                ))
            } else if version.status == 0 {
                let line = version.output.components(separatedBy: .newlines).first ?? "Xcode"
                let detail = developer == nil
                    ? "\(line), but \(xcode) does not contain a developer folder."
                    : "\(line). SwiftNX points nxnative at this Xcode automatically."
                results.append(ToolCheck(
                    id: "xcode",
                    group: .xcode,
                    title: "Xcode",
                    detail: detail + (selectedCLT.contains("CommandLineTools") ? "\nThe system default is Command Line Tools; SwiftNX sets DEVELOPER_DIR for the build." : ""),
                    status: developer == nil ? .missing : .ok,
                    action: developer == nil ? .openXcode : nil,
                    actionLabel: developer == nil ? "Open Xcode" : nil
                ))
            } else {
                results.append(ToolCheck(
                    id: "xcode",
                    group: .xcode,
                    title: "Xcode",
                    detail: version.output.isEmpty ? "xcodebuild could not start." : version.output,
                    status: .blocked,
                    action: .openXcode,
                    actionLabel: "Open Xcode"
                ))
            }
        } else {
            results.append(ToolCheck(
                id: "xcode",
                group: .xcode,
                title: "Xcode",
                detail: "\(xcode) was not found. Install Xcode from the Mac App Store, open it once, and install the Metal Toolchain.",
                status: .missing,
                action: .openXcode,
                actionLabel: "App Store"
            ))
        }

        // Metal toolchain
        let metal = await ToolLocator.runVersionCommand(
            path: "/usr/bin/xcrun",
            arguments: ["-sdk", "macosx", "metal", "--version"],
            xcodePath: xcode
        )
        let metalLower = metal.output.lowercased()
        if metal.status == 0 {
            results.append(ToolCheck(
                id: "metal",
                group: .xcode,
                title: "Metal toolchain",
                detail: metal.output.components(separatedBy: .newlines).first ?? "Metal compiler available.",
                status: .ok
            ))
        } else if metalLower.contains("license") {
            results.append(ToolCheck(
                id: "metal",
                group: .xcode,
                title: "Metal toolchain",
                detail: "Accept the Xcode license first. Then install the toolchain with:\n/usr/bin/xcodebuild -downloadComponent MetalToolchain",
                status: .blocked,
                action: .acceptXcodeLicense,
                actionLabel: "Accept license"
            ))
        } else {
            results.append(ToolCheck(
                id: "metal",
                group: .xcode,
                title: "Metal toolchain",
                detail: "The Metal compiler is not available. Install it once:\nxcodebuild -downloadComponent MetalToolchain\n\n\(metal.output)",
                status: .missing,
                action: .installMetalToolchain,
                actionLabel: "Install toolchain"
            ))
        }

        // Homebrew
        if let brew = ToolLocator.brewPath() {
            results.append(ToolCheck(
                id: "homebrew",
                group: .tools,
                title: "Homebrew",
                detail: brew,
                status: .ok,
                required: false
            ))
        } else {
            results.append(ToolCheck(
                id: "homebrew",
                group: .tools,
                title: "Homebrew",
                detail: "Homebrew is not installed. It provides zstd, glslang and uv; you can also install those another way.",
                status: .warning,
                required: false,
                action: .installHomebrew,
                actionLabel: "Install"
            ))
        }

        // Command line tools
        let git = ToolLocator.find("git")
        results.append(ToolCheck(
            id: "git",
            group: .tools,
            title: "git",
            detail: git ?? "Missing. Needed to clone and update nxnative.",
            status: git == nil ? .missing : .ok,
            action: git == nil ? .installBrewTools : nil,
            actionLabel: git == nil ? "Install tools" : nil
        ))

        let zstd = ToolLocator.find("zstd")
        results.append(ToolCheck(
            id: "zstd",
            group: .tools,
            title: "zstd",
            detail: zstd ?? "Missing. nxnative uses zstd for game archives.",
            status: zstd == nil ? .missing : .ok,
            action: zstd == nil ? .installBrewTools : nil,
            actionLabel: zstd == nil ? "Install tools" : nil
        ))

        let glslang = ToolLocator.find("glslangValidator")
        results.append(ToolCheck(
            id: "glslang",
            group: .tools,
            title: "glslang",
            detail: glslang ?? "Missing. nxnative checks for glslang before a build.",
            status: glslang == nil ? .missing : .ok,
            action: glslang == nil ? .installBrewTools : nil,
            actionLabel: glslang == nil ? "Install tools" : nil
        ))

        let make = ToolLocator.find("make")
        results.append(ToolCheck(
            id: "make",
            group: .tools,
            title: "make",
            detail: make ?? "Missing. Install Xcode's command line tools.",
            status: make == nil ? .missing : .ok
        ))

        let dotnet = ToolLocator.find("dotnet")
        if let dotnet {
            let runtimes = await ToolLocator.runVersionCommand(
                path: dotnet,
                arguments: ["--list-runtimes"],
                xcodePath: xcode
            )
            let has10 = runtimes.output.range(of: "Microsoft.NETCore.App 10.", options: .regularExpression) != nil
            results.append(ToolCheck(
                id: "dotnet",
                group: .tools,
                title: ".NET 10 runtime",
                detail: has10
                    ? (runtimes.output.components(separatedBy: .newlines).first { $0.contains("Microsoft.NETCore.App 10.") } ?? ".NET 10 available.")
                    : "The .NET 10 runtime is missing. nxnative's shader translator needs it.",
                status: has10 ? .ok : .missing,
                action: has10 ? nil : .installDotnet,
                actionLabel: has10 ? nil : "Install .NET"
            ))
        } else {
            results.append(ToolCheck(
                id: "dotnet",
                group: .tools,
                title: ".NET 10 runtime",
                detail: "dotnet was not found. Install the .NET SDK 10 with Homebrew.",
                status: .missing,
                action: .installDotnet,
                actionLabel: "Install .NET"
            ))
        }

        let uv = ToolLocator.find("uv")
        results.append(ToolCheck(
            id: "uv",
            group: .python,
            title: "uv",
            detail: uv ?? "Missing. uv creates SwiftNX's isolated Python environment.",
            status: uv == nil ? .warning : .ok,
            required: false,
            action: uv == nil ? .setupPython : nil,
            actionLabel: uv == nil ? "Set up Python" : nil
        ))

        // Python environment
        if FileManager.default.fileExists(atPath: venvPython.path) {
            let pythonCheck = await ToolLocator.runVersionCommand(
                path: venvPython.path,
                arguments: [
                    "-c",
                    "import sys,lz4.block,capstone,fontTools; import importlib.util as u; assert u.find_spec('compression.zstd') or u.find_spec('backports.zstd'); assert u.find_spec('nsz'); print(sys.version.split()[0])",
                ],
                xcodePath: xcode
            )
            let version = pythonCheck.output.components(separatedBy: .newlines).last ?? ""
            results.append(ToolCheck(
                id: "python",
                group: .python,
                title: "Python build environment",
                detail: pythonCheck.status == 0
                    ? "Python \(version) with lz4, capstone, fonttools and nsz."
                    : "The environment exists but is incomplete:\n\(pythonCheck.output)",
                status: pythonCheck.status == 0 ? .ok : .missing,
                action: pythonCheck.status == 0 ? nil : .setupPython,
                actionLabel: pythonCheck.status == 0 ? nil : "Repair"
            ))
        } else {
            results.append(ToolCheck(
                id: "python",
                group: .python,
                title: "Python build environment",
                detail: "SwiftNX has not created its isolated Python environment yet. Nothing is installed into the system Python.",
                status: .missing,
                action: .setupPython,
                actionLabel: "Set up Python"
            ))
        }

        // nxnative checkout
        let repo = settings.repositoryURL
        let script = repo.appendingPathComponent("scripts/build_ipa_from_nsp.py")
        let repoExists = FileManager.default.fileExists(atPath: repo.path)
        let scriptExists = FileManager.default.fileExists(atPath: script.path)
        if repoExists && scriptExists {
            let isGit = FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path)
            var profileCount = 0
            do {
                let store = try GameProfileStore(repositoryURL: repo)
                profiles = store.profiles
                profileCount = store.profiles.count
                profileError = nil
            } catch {
                profiles = []
                profileError = error.localizedDescription
            }
            results.append(ToolCheck(
                id: "repo",
                group: .project,
                title: "nxnative checkout",
                detail: "\(AppPaths.abbreviate(repo)) — \(profileCount) game profiles.\(isGit ? "" : "\nNot a Git checkout; in-app updates are unavailable.")",
                status: profileCount > 0 ? (isGit ? .ok : .warning) : .missing,
                required: true,
                action: profileCount > 0 ? nil : .cloneRepository,
                actionLabel: profileCount > 0 ? nil : "Choose another folder"
            ))
        } else {
            profiles = []
            results.append(ToolCheck(
                id: "repo",
                group: .project,
                title: "nxnative checkout",
                detail: repoExists
                    ? "The folder exists but scripts/build_ipa_from_nsp.py is missing."
                    : "Clone the nxnative repository. SwiftNX uses it as the porting engine.",
                status: .missing,
                action: .cloneRepository,
                actionLabel: "Clone repository"
            ))
        }

        // Keys
        let keys = settings.keysURL
        let keysOK = keys.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        var keysSize = 0
        if let keys,
           let attributes = try? FileManager.default.attributesOfItem(atPath: keys.path),
           let size = attributes[.size] as? NSNumber {
            keysSize = size.intValue
        }
        results.append(ToolCheck(
            id: "keys",
            group: .files,
            title: "prod.keys",
            detail: keysOK
                ? "\(AppPaths.abbreviate(keys!)) (\(ByteCountFormatter.string(fromByteCount: Int64(keysSize), countStyle: .file)))"
                : "Select the prod.keys file dumped from your own Switch. It stays on this Mac.",
            status: keysOK && keysSize > 0 ? .ok : .missing,
            action: .chooseKeys,
            actionLabel: keysOK ? "Change" : "Choose file"
        ))

        // Disk space
        let volumeURL = FileManager.default.fileExists(atPath: settings.workingRootURL.path)
            ? settings.workingRootURL
            : FileManager.default.homeDirectoryForCurrentUser
        let capacity = try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        let available = capacity ?? 0
        let enough = available >= 10 * 1_000_000_000
        results.append(ToolCheck(
            id: "disk",
            group: .files,
            title: "Free disk space",
            detail: "\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available for the working folder. A build needs roughly twice the game size plus 10 GB.",
            status: enough ? .ok : .warning,
            required: false
        ))

        checks = results
        isChecking = false
        lastChecked = Date()
    }
}

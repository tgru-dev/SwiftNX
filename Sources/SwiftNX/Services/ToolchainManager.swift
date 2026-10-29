import Foundation

@MainActor
final class ToolchainManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isLogPresented = false
    @Published private(set) var title = ""
    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastSucceeded = false

    var onFinished: (() -> Void)?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var hasLog: Bool { !lines.isEmpty || isRunning }

    func dismissLog() {
        guard !isRunning else { return }
        isLogPresented = false
    }

    // MARK: - Public actions

    func installBrewTools() {
        guard begin(title: "Installing build tools") else { return }
        Task {
            let success = await brewInstallSteps()
            await finish(success: success)
        }
    }

    func setupPython() {
        guard begin(title: "Creating Python environment") else { return }
        Task {
            let success = await pythonSetupSteps()
            await finish(success: success)
        }
    }

    func installEverything() {
        guard begin(title: "Setting up SwiftNX") else { return }
        Task {
            guard ToolLocator.brewPath() != nil else {
                append("Homebrew is not installed. Open the Homebrew installer first.", isError: true)
                await finish(success: false, error: "Homebrew is required for the one-click setup.")
                return
            }
            guard await brewInstallSteps() else {
                await finish(success: false)
                return
            }
            guard await pythonSetupSteps() else {
                await finish(success: false)
                return
            }
            append("SwiftNX setup finished.", isError: false)
            await finish(success: true)
        }
    }

    func installMetalToolchain() {
        guard begin(title: "Installing Metal Toolchain") else { return }
        Task {
            guard let developer = ToolLocator.developerDirectory(xcodePath: settings.xcodePath) else {
                await finish(
                    success: false,
                    error: "Xcode was not found at \(settings.xcodePath). Choose Xcode.app in Settings first."
                )
                return
            }

            var environment = ToolLocator.baseEnvironment(xcodePath: settings.xcodePath)
            environment["DEVELOPER_DIR"] = developer

            let downloaded = await runStep(
                label: "Downloading the Metal Toolchain (this can take a while)",
                executable: "/usr/bin/xcodebuild",
                arguments: ["-downloadComponent", "MetalToolchain"],
                environment: environment
            )
            guard downloaded else {
                await finish(
                    success: false,
                    error: "The Metal Toolchain could not be downloaded. If Xcode's license is not accepted yet, do that first.\n\n\(recentOutput)"
                )
                return
            }

            // `-downloadComponent` installs the asset, but Xcode also needs to
            // write XcodeToMetalToolchainIndexMapping.plist for this user.
            // Without that mapping xcrun keeps reporting the compiler missing.
            let registered = await runStep(
                label: "Registering the Metal Toolchain for this user",
                executable: "/usr/bin/xcodebuild",
                arguments: ["-showComponent", "MetalToolchain"],
                environment: environment
            )
            guard registered else {
                await finish(
                    success: false,
                    error: "The toolchain downloaded, but macOS could not register it for this user. Open Xcode once, then try again.\n\n\(recentOutput)"
                )
                return
            }

            // A previous failed lookup can live in xcrun's cache. Clear it so
            // the newly registered toolchain is visible immediately.
            _ = await runStep(
                label: "Refreshing the compiler cache",
                executable: "/usr/bin/xcrun",
                arguments: ["-k"],
                environment: environment
            )

            let verified = await runStep(
                label: "Verifying the Metal compiler",
                executable: "/usr/bin/xcrun",
                arguments: ["--no-cache", "-sdk", "macosx", "metal", "--version"],
                environment: environment
            )
            await finish(
                success: verified,
                error: verified ? nil : "The toolchain is installed, but the Metal compiler is still unavailable. Open Xcode once and retry, or run xcodebuild -showComponent MetalToolchain in Terminal.\n\n\(recentOutput)"
            )
        }
    }

    private var recentOutput: String {
        lines.suffix(8).map(\.text).joined(separator: "\n")
    }

    func cloneRepository() {
        guard begin(title: "Cloning nxnative") else { return }
        Task {
            guard let git = ToolLocator.find("git") else {
                await finish(success: false, error: "git was not found. Install the build tools first.")
                return
            }
            let target = settings.repositoryURL
            let fm = FileManager.default
            if fm.fileExists(atPath: target.path) {
                let contents = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
                if !contents.isEmpty {
                    await finish(success: false, error: "The folder \(target.path) already exists and is not empty. Choose another repository path in Settings.")
                    return
                }
            }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let environment = ToolLocator.baseEnvironment(xcodePath: settings.xcodePath)
            let success = await runStep(
                label: "git clone https://github.com/seedds/nxnative.git",
                executable: URL(fileURLWithPath: git),
                arguments: ["clone", "https://github.com/seedds/nxnative.git", target.path],
                environment: environment,
                currentDirectory: target.deletingLastPathComponent()
            )
            await finish(
                success: success,
                error: success ? nil : "Cloning nxnative failed. Check your network connection and the repository path in Settings."
            )
        }
    }

    // MARK: - External setup

    func openHomebrewInstaller() {
        AppActions.runInTerminal(
            command: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
            title: "Install Homebrew"
        )
    }

    func openDotnetInstaller() {
        AppActions.runInTerminal(
            command: "brew install --cask dotnet-sdk",
            title: "Install the .NET SDK"
        )
    }

    func openXcodeLicense() {
        let developer = ToolLocator.developerDirectory(xcodePath: settings.xcodePath) ?? "/Applications/Xcode.app/Contents/Developer"
        AppActions.runInTerminal(
            command: """
            export DEVELOPER_DIR=\(StreamingProcess.shellQuote(developer))
            sudo /usr/bin/xcodebuild -license accept
            """,
            title: "Accept the Xcode license"
        )
    }

    func openXcode() {
        let app = settings.xcodeURL
        if FileManager.default.fileExists(atPath: app.path) {
            AppActions.openApp(app)
        } else if let url = URL(string: "macappstore://apps.apple.com/app/xcode/id497799835") {
            AppActions.open(url)
        }
    }

    // MARK: - Steps

    private func begin(title: String) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        isLogPresented = true
        self.title = title
        lines = []
        lastError = nil
        lastSucceeded = false
        append(title, isError: false)
        return true
    }

    private func finish(success: Bool, error: String? = nil) async {
        lastSucceeded = success
        lastError = error
        if let error {
            append(error, isError: true)
        }
        append(success ? "Finished successfully." : "Finished with errors.", isError: !success)
        isRunning = false
        onFinished?()
    }

    private func brewInstallSteps() async -> Bool {
        guard let brew = ToolLocator.brewPath() else {
            append("Homebrew is not installed. Install it, then run the setup again.", isError: true)
            return false
        }
        let environment = ToolLocator.baseEnvironment(xcodePath: settings.xcodePath)
        let success = await runStep(
            label: "Installing git, zstd, glslang, uv, xcodegen and lz4",
            executable: URL(fileURLWithPath: brew),
            arguments: ["install", "git", "zstd", "glslang", "uv", "xcodegen", "lz4"],
            environment: environment
        )
        return success
    }

    private func pythonSetupSteps() async -> Bool {
        guard let uv = ToolLocator.find("uv") else {
            append("uv is not installed. Install the build tools first.", isError: true)
            return false
        }
        try? FileManager.default.createDirectory(at: AppPaths.supportDirectory, withIntermediateDirectories: true)
        var environment = ToolLocator.baseEnvironment(xcodePath: settings.xcodePath)
        environment["PYLZ4_USE_SYSTEM_LZ4"] = "0"

        let pythonOK = await runStep(
            label: "Preparing Python 3.14 with uv",
            executable: URL(fileURLWithPath: uv),
            arguments: ["python", "install", "3.14"],
            environment: environment
        )
        guard pythonOK else { return false }

        let venvOK = await runStep(
            label: "Creating \(AppPaths.abbreviate(AppPaths.venvDirectory))",
            executable: URL(fileURLWithPath: uv),
            arguments: ["venv", "--python", "3.14", "--allow-existing", AppPaths.venvDirectory.path],
            environment: environment
        )
        guard venvOK else { return false }

        let packagesOK = await runStep(
            label: "Installing lz4, capstone, fonttools and nsz",
            executable: URL(fileURLWithPath: uv),
            arguments: [
                "pip", "install", "--python", AppPaths.pythonExecutable.path,
                "--upgrade", "lz4", "capstone", "fonttools", "nsz",
            ],
            environment: environment
        )
        guard packagesOK else { return false }

        let verifyOK = await runStep(
            label: "Verifying the Python environment",
            executable: AppPaths.pythonExecutable,
            arguments: [
                "-c",
                "import sys,lz4.block,capstone,fontTools; import importlib.util as u; assert u.find_spec('compression.zstd') or u.find_spec('backports.zstd'); print('Python OK: ' + sys.version.split()[0])",
            ],
            environment: environment
        )
        return verifyOK
    }

    @discardableResult
    private func runStep(
        label: String,
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil
    ) async -> Bool {
        await runStep(
            label: label,
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }

    @discardableResult
    private func runStep(
        label: String,
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil
    ) async -> Bool {
        append(label, isError: false)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            append("Not executable or missing: \(executable.path)", isError: true)
            return false
        }
        let process = StreamingProcess()
        process.onStdout = { [weak self] line in self?.append(line, isError: false) }
        process.onStderr = { [weak self] line in self?.append(line, isError: true) }
        do {
            let status = try await process.run(
                executable: executable,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory
            )
            return status == 0
        } catch {
            append(error.localizedDescription, isError: true)
            return false
        }
    }

    private func append(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        lines.append(LogLine(text: text, isError: isError))
        if lines.count > 5_000 {
            lines.removeFirst(lines.count - 4_000)
        }
    }
}

import Foundation
import Darwin

/// Runs a child process and streams stdout/stderr line by line.
///
/// GUI apps do not inherit the shell's `PATH`, and nxnative is a long-running
/// Python pipeline. A streaming runner keeps the interface responsive and lets
/// SwiftNX show every progress event and the full log.
final class StreamingProcess: @unchecked Sendable {
    private let ioQueue = DispatchQueue(label: "com.swiftnx.streaming-process")
    private let stateLock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    private(set) var isRunning = false
    private(set) var commandDescription = ""

    /// Called on the main queue for every complete stdout line.
    var onStdout: ((String) -> Void)?
    /// Called on the main queue for every complete stderr line.
    var onStderr: ((String) -> Void)?

    @discardableResult
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.qualityOfService = .userInitiated

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        install(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, executable: executable, arguments: arguments)

        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)
        installReader(stdoutPipe, isError: false)
        installReader(stderrPipe, isError: true)

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] terminated in
                guard let self else { return }
                self.ioQueue.async {
                    self.finishReading(stdoutPipe, isError: false)
                    self.finishReading(stderrPipe, isError: true)
                    let status = terminated.terminationStatus
                    DispatchQueue.main.async {
                        self.clearProcess()
                        continuation.resume(returning: status)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    self.clearProcess()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func terminate() {
        guard let process = currentProcess(), process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    func forceKill() {
        guard let process = currentProcess(), process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }

    private func install(
        process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        executable: URL,
        arguments: [String]
    ) {
        stateLock.lock()
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.isRunning = true
        self.commandDescription = ([executable.path] + arguments).map(Self.shellQuote).joined(separator: " ")
        stateLock.unlock()
    }

    private func clearProcess() {
        stateLock.lock()
        isRunning = false
        process = nil
        stateLock.unlock()
    }

    private func currentProcess() -> Process? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process
    }

    private func installReader(_ pipe: Pipe, isError: Bool) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.ioQueue.async {
                self.consume(data, isError: isError)
            }
        }
    }

    private func consume(_ data: Data, isError: Bool) {
        if isError {
            stderrBuffer.append(data)
            emitLines(from: &stderrBuffer, isError: true)
        } else {
            stdoutBuffer.append(data)
            emitLines(from: &stdoutBuffer, isError: false)
        }
    }

    private func emitLines(from buffer: inout Data, isError: Bool) {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            emit(line, isError: isError)
        }
    }

    private func emit(_ line: String, isError: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isError {
                self.onStderr?(line)
            } else {
                self.onStdout?(line)
            }
        }
    }

    private func finishReading(_ pipe: Pipe, isError: Bool) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil
        let remainder = handle.availableData
        if !remainder.isEmpty {
            if isError {
                stderrBuffer.append(remainder)
                emitLines(from: &stderrBuffer, isError: true)
            } else {
                stdoutBuffer.append(remainder)
                emitLines(from: &stdoutBuffer, isError: false)
            }
        }
        if isError {
            if !stderrBuffer.isEmpty {
                let line = String(decoding: stderrBuffer, as: UTF8.self)
                stderrBuffer.removeAll(keepingCapacity: true)
                if !line.isEmpty { emit(line, isError: true) }
            }
        } else {
            if !stdoutBuffer.isEmpty {
                let line = String(decoding: stdoutBuffer, as: UTF8.self)
                stdoutBuffer.removeAll(keepingCapacity: true)
                if !line.isEmpty { emit(line, isError: false) }
            }
        }
    }

    static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-:=@%+,")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct CommandResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }
    var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

enum CommandRunner {
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var stdoutLines: [String] = []
        private var stderrLines: [String] = []

        func append(_ line: String, isError: Bool) {
            lock.lock()
            if isError { stderrLines.append(line) } else { stdoutLines.append(line) }
            lock.unlock()
        }

        func result(status: Int32) -> CommandResult {
            lock.lock()
            defer { lock.unlock() }
            return CommandResult(
                status: status,
                stdout: stdoutLines.joined(separator: "\n"),
                stderr: stderrLines.joined(separator: "\n")
            )
        }
    }

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> CommandResult {
        let collector = Collector()
        let process = StreamingProcess()
        process.onStdout = { collector.append($0, isError: false) }
        process.onStderr = { collector.append($0, isError: true) }
        let status = try await process.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
        return collector.result(status: status)
    }

    static func run(
        path: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> CommandResult {
        try await run(
            executable: URL(fileURLWithPath: path),
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }
}

@preconcurrency import Darwin
import Foundation

enum FFmpegCommandRunnerError: LocalizedError {
    case executionFailed(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .executionFailed(code, message):
            let detail = message.isEmpty ? "The FFmpeg command failed." : message
            return "Command failed with exit code \(code). \(detail)"
        }
    }
}

actor FFmpegCommandRunner {
    static let shared = FFmpegCommandRunner()
    private static let executionLock = NSLock()
    private static let lockAcquireTimeout: TimeInterval = 2
    private static let hardCommandTimeout: TimeInterval = 600

    func runFFprobe(arguments: [String]) async throws -> String {
        try await execute(arguments: arguments, command: .ffprobe).stdout
    }

    func runFFmpegInfoAllowingFailure(arguments: [String]) async -> String {
        do {
            return try await execute(arguments: arguments, command: .ffmpeg).stderr
        } catch let FFmpegCommandRunnerError.executionFailed(_, message) {
            return message
        } catch {
            return error.localizedDescription
        }
    }

    func runFFmpeg(
        arguments: [String],
        onProgress: @escaping @Sendable ([String: String]) -> Void,
        onLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let progressPrefix = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-progress", "pipe:1"]
        let userArguments = arguments.dropFirst().filter { $0 != "-nostdin" }
        let mergedArguments = progressPrefix + userArguments

        return try await execute(
            arguments: mergedArguments,
            command: .ffmpeg,
            stdoutLineHandler: { line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }

            let key = parts[0]
            guard key == "out_time_ms" || key == "out_time_us" || key == "progress" else { return }

            onProgress([key: parts[1]])
            },
            stderrLineHandler: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !Self.isFrameworkNoiseLine(trimmed) else { return }
                onLog?(trimmed)
            }
        ).stderr
    }

    func runFFmpegWithoutProgress(
        arguments: [String],
        onLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let basePrefix = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostats", "-nostdin"]
        let userArguments = arguments.dropFirst().filter { $0 != "-nostdin" }
        let mergedArguments = basePrefix + userArguments

        return try await execute(
            arguments: mergedArguments,
            command: .ffmpeg,
            stderrLineHandler: { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !Self.isFrameworkNoiseLine(trimmed) else { return }
                onLog?(trimmed)
            }
        ).stderr
    }

    private func execute(
        arguments: [String],
        command: Command,
        stdoutLineHandler: (@Sendable (String) -> Void)? = nil,
        stderrLineHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> (stdout: String, stderr: String) {
        let commandName = Self.commandName(for: command)
        let runID = String(UUID().uuidString.prefix(8))

        Self.emitRunnerLog("[\(runID)] START \(commandName): \(Self.formatArguments(arguments))")

        let timeoutNanoseconds = UInt64(Self.hardCommandTimeout * 1_000_000_000)
        do {
            let result = try await withThrowingTaskGroup(of: (stdout: String, stderr: String).self) { group in
                group.addTask {
                    try Self.executeSynchronously(
                        arguments: arguments,
                        command: command,
                        runID: runID,
                        stdoutLineHandler: stdoutLineHandler,
                        stderrLineHandler: stderrLineHandler
                    )
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw FFmpegCommandRunnerError.executionFailed(
                        code: -110,
                        message: "[\(runID)] \(commandName) timed out after \(Int(Self.hardCommandTimeout)) seconds. Restart the app to reset FFmpeg state if this repeats."
                    )
                }

                guard let first = try await group.next() else {
                    throw FFmpegCommandRunnerError.executionFailed(code: -1, message: "\(commandName) returned no result.")
                }

                group.cancelAll()
                return first
            }

            Self.emitRunnerLog("[\(runID)] SUCCESS \(commandName)")
            return result
        } catch {
            Self.emitRunnerLog("[\(runID)] ERROR \(commandName): \(error.localizedDescription)")
            throw error
        }
    }

    private static func executeSynchronously(
        arguments: [String],
        command: Command,
        runID: String,
        stdoutLineHandler: (@Sendable (String) -> Void)?,
        stderrLineHandler: (@Sendable (String) -> Void)?
    ) throws -> (stdout: String, stderr: String) {
        let commandName = commandName(for: command)
        emitRunnerLog("[\(runID)] STEP 1 \(commandName): waiting for backend lock")

        guard executionLock.lock(before: Date().addingTimeInterval(lockAcquireTimeout)) else {
            throw FFmpegCommandRunnerError.executionFailed(
                code: -55,
                message: "[\(runID)] FFmpeg backend is busy or stuck from a previous run. Force close and reopen the app, then retry."
            )
        }
        defer { executionLock.unlock() }

        emitRunnerLog("[\(runID)] STEP 2 \(commandName): backend lock acquired")

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = OutputCollector(lineHandler: stdoutLineHandler)
        let stderrCollector = OutputCollector(lineHandler: stderrLineHandler)
        var didCleanup = false
        var capturedOutput = (stdout: "", stderr: "")

        let stdoutReader = stdoutPipe.fileHandleForReading
        let stderrReader = stderrPipe.fileHandleForReading

        stdoutReader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stdoutCollector.append(data: data)
        }

        stderrReader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            stderrCollector.append(data: data)
        }

        let originalStdout = dup(STDOUT_FILENO)
        let originalStderr = dup(STDERR_FILENO)

        guard originalStdout != -1, originalStderr != -1 else {
            throw FFmpegCommandRunnerError.executionFailed(code: -1, message: "Unable to duplicate standard file descriptors.")
        }

        emitRunnerLog("[\(runID)] STEP 3 \(commandName): pipes prepared and file descriptors duplicated")

        func finalizePipes() {
            guard !didCleanup else { return }
            didCleanup = true

            fflush(nil)
            dup2(originalStdout, STDOUT_FILENO)
            dup2(originalStderr, STDERR_FILENO)
            close(originalStdout)
            close(originalStderr)

            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()

            stdoutCollector.append(data: stdoutReader.readDataToEndOfFile())
            stderrCollector.append(data: stderrReader.readDataToEndOfFile())

            stdoutReader.readabilityHandler = nil
            stderrReader.readabilityHandler = nil

            capturedOutput = (stdoutCollector.finish(), stderrCollector.finish())
        }

        defer {
            finalizePipes()
        }

        emitRunnerLog("[\(runID)] STEP 4 \(commandName): resetting CLI parser state")
        Self.resetCLIParserState()
        emitRunnerLog("[\(runID)] STEP 5 \(commandName): redirecting stdio and invoking bridge")

        dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        do {
            let exitCode: Int
            switch command {
            case .ffmpeg:
                exitCode = OfficialFFmpegBridge.runFFmpeg(arguments: arguments)
            case .ffprobe:
                exitCode = OfficialFFmpegBridge.runFFprobe(arguments: arguments)
            }

            finalizePipes()
            emitRunnerLog("[\(runID)] STEP 6 \(commandName): bridge returned exit=\(exitCode), stdoutChars=\(capturedOutput.stdout.count), stderrChars=\(capturedOutput.stderr.count)")

            if exitCode == OfficialFFmpegBridge.bridgeNotLinkedExitCode {
                throw FFmpegCommandRunnerError.executionFailed(
                    code: exitCode,
                    message: "Official FFmpeg bridge symbols are missing (backend: \(OfficialFFmpegBridge.backendDescription())). Build and link official FFmpeg iOS artifacts first."
                )
            }

            guard exitCode == 0 else {
                throw FFmpegCommandRunnerError.executionFailed(
                    code: exitCode,
                    message: filteredCommandMessage(stdout: capturedOutput.stdout, stderr: capturedOutput.stderr)
                )
            }

            return capturedOutput
        } catch {
            if let knownError = error as? FFmpegCommandRunnerError {
                throw knownError
            }

            throw FFmpegCommandRunnerError.executionFailed(
                code: -1,
                message: filteredCommandMessage(stdout: capturedOutput.stdout, stderr: capturedOutput.stderr, fallback: error.localizedDescription)
            )
        }
    }

    private static func filteredCommandMessage(stdout: String, stderr: String, fallback: String = "") -> String {
        let combined = [stderr, stdout]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        let cleaned = sanitizeFrameworkNoise(from: combined)
        if !cleaned.isEmpty {
            return cleaned
        }

        if !fallback.isEmpty {
            return fallback
        }

        return "The FFmpeg command failed."
    }

    private static func sanitizeFrameworkNoise(from text: String) -> String {
        let cleanedLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !isFrameworkNoiseLine(line)
            }

        return cleanedLines.joined(separator: "\n")
    }

    private static func resetCLIParserState() {
        optind = 1
        opterr = 1
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        optreset = 1
        #endif
    }

    private static func isFrameworkNoiseLine(_ line: String) -> Bool {
        let noiseMarkers = [
            "HookMain:",
            "FFmpeg_exit=",
            "OSLOG-",
            "Gesture: System gesture gate timed out.",
            "UIContextMenuInteraction updateVisibleMenuWithBlock",
            "Plugin query method called",
            "Invalidation handler invoked",
            "personaAttributesForPersonaType",
            "LaunchServices:",
            "Attempt to map database failed",
            "process may not map database",
            "Failed to initialize client context",
            "Logging Error: Failed to receive",
            "<<<< FigApplicationStateMonitor >>>>"
        ]

        return noiseMarkers.contains(where: { line.contains($0) })
    }

    private static func formatArguments(_ arguments: [String]) -> String {
        arguments
            .map { argument in
                if argument.contains(" ") {
                    return "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                return argument
            }
            .joined(separator: " ")
    }

    private static func commandName(for command: Command) -> String {
        switch command {
        case .ffmpeg:
            return "ffmpeg"
        case .ffprobe:
            return "ffprobe"
        }
    }

    private static func emitRunnerLog(_ message: String) {
        #if DEBUG
        print("[catMedia][FFmpegRunner] \(message)")
        #endif
    }
}

private enum Command {
    case ffmpeg
    case ffprobe
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let lineHandler: (@Sendable (String) -> Void)?
    nonisolated(unsafe) private var data = Data()
    nonisolated(unsafe) private var pendingLine = ""

    nonisolated init(lineHandler: (@Sendable (String) -> Void)? = nil) {
        self.lineHandler = lineHandler
    }

    nonisolated func append(data newData: Data) {
        guard !newData.isEmpty else { return }

        let linesToSend: [String]

        lock.lock()
        data.append(newData)

        if let text = String(data: newData, encoding: .utf8) {
            pendingLine += text
            let segments = pendingLine.components(separatedBy: .newlines)
            pendingLine = segments.last ?? ""
            linesToSend = Array(segments.dropLast()).filter { !$0.isEmpty }
        } else {
            linesToSend = []
        }
        lock.unlock()

        linesToSend.forEach { lineHandler?($0) }
    }

    nonisolated func finish() -> String {
        let pendingToSend: String?

        lock.lock()
        pendingToSend = pendingLine.isEmpty ? nil : pendingLine
        pendingLine = ""
        let result = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()

        if let pendingToSend {
            lineHandler?(pendingToSend)
            return result.isEmpty ? pendingToSend : result
        }

        return result
    }
}


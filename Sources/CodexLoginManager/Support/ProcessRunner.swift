import Foundation

enum ProcessRunnerError: LocalizedError {
    case timedOut(command: String, seconds: TimeInterval)
    case launchFailed(command: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .timedOut(command, seconds):
            return L10n.format("process.timed_out", command, Int(seconds))
        case let .launchFailed(command, underlying):
            return L10n.format("process.launch_failed", command, underlying.localizedDescription)
        }
    }
}

struct ProcessRunner: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
            // npm entrypoints use /usr/bin/env node; Finder does not inherit nvm's PATH.
            let executableDirectory = URL(fileURLWithPath: executablePath)
                .deletingLastPathComponent().path
            environment["PATH"] = [
                executableDirectory,
                "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            ].joined(separator: ":")
            process.environment = environment

            do {
                try process.run()
            } catch {
                throw ProcessRunnerError.launchFailed(command: executablePath, underlying: error)
            }

            if let timeoutSeconds {
                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while process.isRunning && Date() < deadline {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }

                if process.isRunning {
                    process.terminate()
                    throw ProcessRunnerError.timedOut(command: executablePath, seconds: timeoutSeconds)
                }
            } else {
                process.waitUntilExit()
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }.value
    }
}

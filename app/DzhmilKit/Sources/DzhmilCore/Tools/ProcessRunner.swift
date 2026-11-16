import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
}

public enum ProcessRunner {
    public static let outputCap = 1_048_576

    public static func run(_ executable: String, _ args: [String], timeout: Duration = .seconds(30)) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable, args, timeout: timeout))
            }
        }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var closed = false
        let done = DispatchSemaphore(value: 0)

        func append(_ chunk: Data) {
            lock.withLock {
                guard !closed else { return }
                if chunk.isEmpty {
                    closed = true
                    done.signal()
                } else if data.count < ProcessRunner.outputCap {
                    data.append(chunk.prefix(ProcessRunner.outputCap - data.count))
                }
            }
        }

        var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    private static func runBlocking(_ executable: String, _ args: [String], timeout: Duration) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let out = Collector(), err = Collector()
        outPipe.fileHandleForReading.readabilityHandler = { out.append($0.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { err.append($0.availableData) }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        let timedOut = Flag()
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }

        process.waitUntilExit()
        let drainWait: DispatchTime = .now() + (timedOut.isSet ? 0.3 : 2)
        _ = out.done.wait(timeout: drainWait)
        _ = err.done.wait(timeout: drainWait)
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        return ProcessResult(exitCode: process.terminationStatus, stdout: out.string, stderr: err.string, timedOut: timedOut.isSet)
    }
}

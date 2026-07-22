import Darwin
import Foundation

struct ProcessCommandResult: Equatable {
    let output: String
    let terminationStatus: Int32
    let wasCancelled: Bool
    let timedOut: Bool

    static let cancelled = ProcessCommandResult(
        output: "",
        terminationStatus: -1,
        wasCancelled: true,
        timedOut: false
    )
}

final class ProcessCommandRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var cancelled = false

    var activeProcessCount: Int {
        lock.withLock { processes.count }
    }

    func run(_ path: String, arguments: [String], timeout: TimeInterval) -> ProcessCommandResult {
        guard !lock.withLock({ cancelled }) else { return .cancelled }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return ProcessCommandResult(
                output: "",
                terminationStatus: -1,
                wasCancelled: false,
                timedOut: false
            )
        }

        let identifier = ObjectIdentifier(process)
        let shouldCancel = lock.withLock { () -> Bool in
            if cancelled {
                return true
            }
            processes[identifier] = process
            return false
        }

        if shouldCancel {
            terminate(process)
            return .cancelled
        }

        let outputData = LockedBox(Data())
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputData.set(data)
            outputGroup.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if lock.withLock({ cancelled }) {
                break
            }
            if Date() >= deadline {
                timedOut = true
                terminate(process)
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        process.waitUntilExit()
        _ = outputGroup.wait(timeout: .now() + 1)
        _ = lock.withLock {
            processes.removeValue(forKey: identifier)
        }

        let wasCancelled = lock.withLock { cancelled }
        let data = outputData.get()
        return ProcessCommandResult(
            output: String(data: data, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus,
            wasCancelled: wasCancelled,
            timedOut: timedOut
        )
    }

    func cancelAll() {
        let running = lock.withLock { () -> [Process] in
            cancelled = true
            return Array(processes.values)
        }
        running.forEach(terminate)
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        let deadline = Date().addingTimeInterval(0.25)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ value: Value) {
        lock.withLock {
            self.value = value
        }
    }

    func get() -> Value {
        lock.withLock { value }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

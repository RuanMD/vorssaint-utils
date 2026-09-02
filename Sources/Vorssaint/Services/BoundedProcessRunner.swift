// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var exceeded = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        if data.count + chunk.count > limit { exceeded = true }
        let available = max(0, limit - data.count)
        if available > 0 { data.append(chunk.prefix(available)) }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    var didExceed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceeded
    }
}

enum BoundedProcessRunner {
    struct Result {
        let status: Int32
        let output: Data
        let errorOutput: Data
        let timedOut: Bool
        let outputExceeded: Bool
        let cancelled: Bool
    }

    static func run(_ path: String,
                    _ arguments: [String],
                    timeout: TimeInterval,
                    maxOutputBytes: Int,
                    input: Data = Data(),
                    isCancelled: (() -> Bool)? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        let output = BoundedProcessOutput(limit: maxOutputBytes)
        func drain(_ reader: FileHandle, into output: BoundedProcessOutput,
                   signal: DispatchSemaphore) {
            reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                signal.signal()
            } else {
                // Keep draining after the retained prefix is full so the child
                // can never block on a full pipe or turn output into memory use.
                output.append(chunk)
            }
            }
        }
        let outputReader = outputPipe.fileHandleForReading
        let errorOutput = BoundedProcessOutput(limit: maxOutputBytes)
        let errorReader = errorPipe.fileHandleForReading
        let outputDrained = DispatchSemaphore(value: 0)
        let errorDrained = DispatchSemaphore(value: 0)
        drain(outputReader, into: output, signal: outputDrained)
        drain(errorReader, into: errorOutput, signal: errorDrained)

        // The child is watched through its termination handler. A blocking
        // `waitUntilExit()` has to be parked on a thread of its own, and the
        // timeout below makes `run` walk away from it while it still holds one
        // worker of the shared 64-thread pool. Those abandoned waits pile up
        // faster than they drain, and a full pool starves every later user of
        // it, the main thread's window walk included (issue #971). It also
        // starves this runner, which then reports timeouts for commands that
        // exited at once and abandons another wait doing it. A termination
        // handler occupies no thread, so none of that accumulates.
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            outputReader.readabilityHandler = nil
            errorReader.readabilityHandler = nil
            try? outputReader.close()
            try? errorReader.close()
            return Result(status: -1, output: Data(), errorOutput: Data(), timedOut: false,
                          outputExceeded: false, cancelled: false)
        }

        if !input.isEmpty { try? inputPipe.fileHandleForWriting.write(contentsOf: input) }
        try? inputPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(max(0, timeout))
        var didFinish = false
        var cancelled = false
        while Date() < deadline {
            if isCancelled?() == true { cancelled = true; break }
            if finished.wait(timeout: .now() + 0.01) == .success { didFinish = true; break }
        }
        let timedOut = !didFinish
        if timedOut || cancelled {
            process.terminate()
            didFinish = finished.wait(timeout: .now() + 0.5) == .success
            if !didFinish {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
        }

        // A child may inherit stdout after the command itself exits. Give an
        // ordinary EOF a moment to deliver the tail, then close our descriptor
        // so that inherited handle cannot leave a reader alive indefinitely.
        _ = outputDrained.wait(timeout: .now() + 0.2)
        _ = errorDrained.wait(timeout: .now() + 0.2)
        outputReader.readabilityHandler = nil
        errorReader.readabilityHandler = nil
        try? outputReader.close()
        try? errorReader.close()

        return Result(status: timedOut || cancelled ? -1 : process.terminationStatus,
                      output: output.value(),
                      errorOutput: errorOutput.value(),
                      timedOut: timedOut && !cancelled,
                      outputExceeded: output.didExceed || errorOutput.didExceed,
                      cancelled: cancelled)
    }
}

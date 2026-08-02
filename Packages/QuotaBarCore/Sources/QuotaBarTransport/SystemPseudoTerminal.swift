import Darwin
import Dispatch
import Foundation

final class ProcessExitGate: @unchecked Sendable {
    private let lock = NSLock()
    private let timers = DispatchQueue(label: "com.renanravelli.QuotaBar.processexit")
    private var recorded: Int32?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [@Sendable () -> Void] = []

    var status: Int32? {
        lock.withLock { recorded }
    }

    func attach(to process: Process) {
        process.terminationHandler = { [self] finished in
            let notify: [@Sendable () -> Void] = lock.withLock {
                recorded = finished.terminationStatus
                defer { observers.removeAll() }
                return observers
            }
            release()
            notify.forEach { $0() }
        }
    }

    func observeExit(_ notify: @escaping @Sendable () -> Void) {
        let alreadyExited: Bool = lock.withLock {
            guard recorded == nil else { return true }
            observers.append(notify)
            return false
        }
        if alreadyExited { notify() }
    }

    func wait(within grace: Duration) async {
        guard status == nil else { return }

        let expiry = DispatchWorkItem { [weak self] in self?.release() }
        timers.asyncAfter(deadline: .now() + .nanoseconds(Self.nanoseconds(in: grace)), execute: expiry)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let settled: Bool = lock.withLock {
                guard recorded == nil else { return true }
                waiters.append(continuation)
                return false
            }
            if settled { continuation.resume() }
        }
        expiry.cancel()
    }

    private static func nanoseconds(in duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000)
    }

    private func release() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            defer { waiters.removeAll() }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}

final class SystemPseudoTerminalSession: PseudoTerminalSession, @unchecked Sendable {
    private static let readLength = 1 << 16

    private let master: Int32
    private let process: Process
    private let exit: ProcessExitGate
    private let terminationGrace: Duration
    private let events = DispatchQueue(label: "com.renanravelli.QuotaBar.pseudoterminal")
    private let readSource: DispatchSourceRead
    private let incoming: UnsafeMutableRawBufferPointer
    private let lock = NSLock()

    private var isOpen = true
    private var isSourceIdle = true
    private var hasChildExited = false
    private var reader: CheckedContinuation<Void, Never>?

    init(master: Int32, slave: Int32, process: Process, exit: ProcessExitGate, terminationGrace: Duration) {
        self.master = master
        self.process = process
        self.exit = exit
        self.terminationGrace = terminationGrace
        incoming = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.readLength, alignment: 1)
        SecretBuffer.zero(incoming)
        readSource = DispatchSource.makeReadSource(fileDescriptor: master, queue: events)

        readSource.setEventHandler { [weak self] in self?.wakeReader() }
        readSource.setCancelHandler { close(master); close(slave) }
        exit.observeExit { [weak self] in self?.noteChildExit() }
    }

    deinit {
        closeTerminal()
        SecretBuffer.zero(incoming)
        incoming.deallocate()
    }

    var processIdentifier: Int32 { process.processIdentifier }

    func readChunk(_ consume: (UnsafeRawBufferPointer) -> Void) async throws -> Bool {
        while lock.withLock({ isOpen }) {
            if Task.isCancelled { return false }

            let nothingMoreCanArrive = lock.withLock { hasChildExited }
            let received = read(master, incoming.baseAddress, incoming.count)

            if received > 0 {
                consume(UnsafeRawBufferPointer(rebasing: incoming[0..<received]))
                SecretBuffer.zero(UnsafeMutableRawBufferPointer(rebasing: incoming[0..<received]))
                return true
            }
            if received == 0 { return false }

            switch errno {
            case EINTR:
                continue
            case EAGAIN, EWOULDBLOCK:
                if nothingMoreCanArrive { return false }
                await waitUntilReadable()
            default:
                return false
            }
        }

        return false
    }

    func write(_ bytes: UnsafeRawBufferPointer) async throws {
        guard let base = bytes.baseAddress else { return }

        var delivered = 0
        while delivered < bytes.count {
            let written = Darwin.write(master, base + delivered, bytes.count - delivered)
            if written > 0 {
                delivered += written
                continue
            }

            switch errno {
            case EINTR:
                continue
            case EAGAIN, EWOULDBLOCK:
                await Task.yield()
            default:
                throw PseudoTerminalFailure.cannotWrite
            }
        }
    }

    func terminate() async {
        if process.isRunning { kill(process.processIdentifier, SIGTERM) }
        await exit.wait(within: terminationGrace)

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            await exit.wait(within: terminationGrace)
        }

        closeTerminal()
    }

    func exitStatus() async -> Int32? {
        exit.status
    }

    private func waitUntilReadable() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let settled: Bool = lock.withLock {
                    guard isOpen, !hasChildExited, !Task.isCancelled else { return true }
                    reader = continuation
                    if isSourceIdle {
                        isSourceIdle = false
                        readSource.resume()
                    }
                    return false
                }
                if settled { continuation.resume() }
            }
        } onCancel: {
            wakeReader()
        }
    }

    private func wakeReader() {
        let woken: CheckedContinuation<Void, Never>? = lock.withLock {
            if !isSourceIdle, isOpen {
                isSourceIdle = true
                readSource.suspend()
            }
            defer { reader = nil }
            return reader
        }
        woken?.resume()
    }

    private func noteChildExit() {
        lock.withLock { hasChildExited = true }
        wakeReader()
    }

    private func closeTerminal() {
        var wasOpen = false
        let woken: CheckedContinuation<Void, Never>? = lock.withLock {
            guard isOpen else { return nil }
            isOpen = false
            wasOpen = true
            if isSourceIdle {
                isSourceIdle = false
                readSource.resume()
            }
            defer { reader = nil }
            return reader
        }

        guard wasOpen else { return }
        readSource.cancel()
        woken?.resume()
    }
}

public struct SystemPseudoTerminal: PseudoTerminalSpawning {
    private let terminationGrace: Duration

    public init(terminationGrace: Duration = AssistedSetupTiming.standard.terminationGrace) {
        self.terminationGrace = terminationGrace
    }

    public func spawn(_ command: TerminalCommand) throws -> any PseudoTerminalSession {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw PseudoTerminalFailure.cannotOpenTerminal
        }

        do {
            try Self.widen(to: command.window, on: master)
            try Self.silenceEcho(on: slave)
        } catch {
            close(master)
            close(slave)
            throw error
        }

        let child = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardInput = child
        process.standardOutput = child
        process.standardError = child

        let exit = ProcessExitGate()
        exit.attach(to: process)

        do {
            try process.run()
        } catch {
            close(master)
            close(slave)
            throw PseudoTerminalFailure.cannotLaunch
        }

        return SystemPseudoTerminalSession(
            master: master,
            slave: slave,
            process: process,
            exit: exit,
            terminationGrace: terminationGrace
        )
    }

    private static func widen(to window: TerminalWindow, on master: Int32) throws {
        var size = winsize(ws_row: window.rows, ws_col: window.columns, ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(master, TIOCSWINSZ, &size) == 0, fcntl(master, F_SETFL, O_NONBLOCK) == 0 else {
            throw PseudoTerminalFailure.cannotConfigureTerminal
        }
    }

    private static func silenceEcho(on slave: Int32) throws {
        var settings = termios()
        guard tcgetattr(slave, &settings) == 0 else { throw PseudoTerminalFailure.cannotConfigureTerminal }

        settings.c_lflag &= ~tcflag_t(ECHO | ICANON)
        guard tcsetattr(slave, TCSANOW, &settings) == 0 else { throw PseudoTerminalFailure.cannotConfigureTerminal }
    }
}

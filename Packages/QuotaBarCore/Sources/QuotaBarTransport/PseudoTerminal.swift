import Foundation

public struct TerminalWindow: Sendable, Hashable {
    public static let wide = TerminalWindow(columns: 512, rows: 200)

    public let columns: UInt16
    public let rows: UInt16

    public init(columns: UInt16, rows: UInt16) {
        self.columns = columns
        self.rows = rows
    }
}

public struct TerminalCommand: Sendable, Hashable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL
    public let window: TerminalWindow

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        window: TerminalWindow
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.window = window
    }

    public static func setupToken(claudeCode: URL, home: URL) -> TerminalCommand {
        TerminalCommand(
            executable: claudeCode,
            arguments: ["setup-token"],
            environment: [
                "HOME": home.path(percentEncoded: false),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8"
            ],
            workingDirectory: home,
            window: .wide
        )
    }
}

public enum PseudoTerminalFailure: Error, Sendable, Hashable {
    case cannotOpenTerminal
    case cannotConfigureTerminal
    case cannotLaunch
    case cannotWrite
}

public protocol PseudoTerminalSpawning: Sendable {
    func spawn(_ command: TerminalCommand) throws -> any PseudoTerminalSession
}

public protocol PseudoTerminalSession: Sendable {
    func readChunk(_ consume: (UnsafeRawBufferPointer) -> Void) async throws -> Bool
    func write(_ bytes: UnsafeRawBufferPointer) async throws
    func terminate() async
    func exitStatus() async -> Int32?
}

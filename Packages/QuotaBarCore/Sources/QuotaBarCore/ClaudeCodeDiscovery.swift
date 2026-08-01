import Foundation

public enum ClaudeCodeCandidatePath: Sendable, Hashable {
    case userRelative(String)
    case absolute(String)

    public static let ordered: [ClaudeCodeCandidatePath] = [
        .userRelative(".local/bin/claude"),
        .userRelative(".claude/local/claude"),
        .absolute("/opt/homebrew/bin/claude"),
        .absolute("/usr/local/bin/claude"),
        .userRelative(".nvm/versions/node/*/bin/claude")
    ]
}

public struct ClaudeCodeExecutable: Sendable, Hashable {
    public let path: String
    public let modifiedAt: Date
    public let size: Int

    public init(path: String, modifiedAt: Date, size: Int) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.size = size
    }
}

public struct ClaudeCodeInstallation: Sendable, Hashable {
    public let version: String
    public let executable: ClaudeCodeExecutable

    public init(version: String, executable: ClaudeCodeExecutable) {
        self.version = version
        self.executable = executable
    }
}

public enum ClaudeCodeDiscovery: Sendable, Hashable {
    case installed(ClaudeCodeInstallation)
    case notFound

    public var version: String? {
        switch self {
        case .installed(let installation): installation.version
        case .notFound: nil
        }
    }

    public var allowsProbe: Bool {
        version != nil
    }
}

public protocol ClaudeCodeEnvironment: Sendable {
    func executables(at candidate: ClaudeCodeCandidatePath) -> [ClaudeCodeExecutable]
    func versionOutput(of executable: ClaudeCodeExecutable) -> String?
}

import Foundation

public enum ClaudeCodeVersion {
    public static func parse(_ output: String) -> String? {
        let reported = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = reported.prefixMatch(of: /\d+\.\d+\.\d+[\w.\-+]*/) else { return nil }
        return String(match.output)
    }
}

public struct ClaudeCodeVersionResolver: Sendable {
    private let environment: any ClaudeCodeEnvironment
    private var known: ClaudeCodeInstallation?

    public init(environment: any ClaudeCodeEnvironment) {
        self.environment = environment
    }

    public mutating func resolve() -> ClaudeCodeDiscovery {
        guard let executable = locate() else {
            known = nil
            return .notFound
        }
        if let known, known.executable == executable {
            return .installed(known)
        }
        guard let output = environment.versionOutput(of: executable),
              let version = ClaudeCodeVersion.parse(output)
        else {
            known = nil
            return .notFound
        }

        let installation = ClaudeCodeInstallation(version: version, executable: executable)
        known = installation
        return .installed(installation)
    }

    private func locate() -> ClaudeCodeExecutable? {
        for candidate in ClaudeCodeCandidatePath.ordered {
            if let executable = environment.executables(at: candidate).first { return executable }
        }
        return nil
    }
}

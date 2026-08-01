import Foundation
import QuotaBarCore

public struct SystemClaudeCodeEnvironment: ClaudeCodeEnvironment {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public func executables(at candidate: ClaudeCodeCandidatePath) -> [ClaudeCodeExecutable] {
        Self.expanding(path(of: candidate)).compactMap(Self.executable(at:))
    }

    public func versionOutput(of executable: ClaudeCodeExecutable) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: executable.path)
        process.arguments = ["--version"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let reported = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: reported, encoding: .utf8)
    }

    private func path(of candidate: ClaudeCodeCandidatePath) -> String {
        switch candidate {
        case .absolute(let path): path
        case .userRelative(let path): home.appending(path: path).path(percentEncoded: false)
        }
    }

    private static func expanding(_ path: String) -> [String] {
        var expanded = [""]

        for component in path.split(separator: "/") {
            guard component == "*" else {
                expanded = expanded.map { "\($0)/\(component)" }
                continue
            }
            expanded = expanded.flatMap(children(of:))
        }

        return expanded
    }

    private static func children(of directory: String) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.isEmpty ? "/" : directory)) ?? []
        return contents.sorted().map { "\(directory)/\($0)" }
    }

    private static func executable(at path: String) -> ClaudeCodeExecutable? {
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: path) else { return nil }

        let resolved = URL(filePath: path).resolvingSymlinksInPath().path(percentEncoded: false)
        guard let attributes = try? manager.attributesOfItem(atPath: resolved),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int
        else { return nil }

        return ClaudeCodeExecutable(path: path, modifiedAt: modifiedAt, size: size)
    }
}

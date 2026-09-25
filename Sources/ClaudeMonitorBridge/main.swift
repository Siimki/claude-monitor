import Foundation
import ClaudeMonitorCore

private struct BridgeConfig: Codable {
    let originalStatusLineJSON: Data?
    let originalCommand: String?
}

private enum BridgeError: Error, CustomStringConvertible {
    case invalidSettings
    case invalidStatusLine

    var description: String {
        switch self {
        case .invalidSettings: return "Claude settings must contain a JSON object."
        case .invalidStatusLine: return "The existing statusLine setting is not a JSON object."
        }
    }
}

private let fm = FileManager.default
private let supportDirectory = ProcessInfo.processInfo.environment["CLAUDE_MONITOR_SUPPORT_DIR"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? UsageCache.directoryURL
private let configURL = supportDirectory.appendingPathComponent("bridge-config.json")
private let settingsURL = ProcessInfo.processInfo.environment["CLAUDE_MONITOR_SETTINGS_PATH"]
    .map { URL(fileURLWithPath: $0) }
    ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

private func absoluteExecutablePath() -> String {
    let raw = CommandLine.arguments[0]
    if raw.hasPrefix("/") { return URL(fileURLWithPath: raw).standardizedFileURL.path }
    return URL(fileURLWithPath: fm.currentDirectoryPath)
        .appendingPathComponent(raw).standardizedFileURL.path
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func readSettings() throws -> [String: Any] {
    guard fm.fileExists(atPath: settingsURL.path) else { return [:] }
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL))
    guard let settings = value as? [String: Any] else { throw BridgeError.invalidSettings }
    return settings
}

private func writeJSONObject(_ object: Any, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try data.write(to: url, options: .atomic)
}

private func install() throws {
    let executable = absoluteExecutablePath()
    var settings = try readSettings()
    if let statusLine = settings["statusLine"], !(statusLine is [String: Any]) {
        throw BridgeError.invalidStatusLine
    }
    let current = settings["statusLine"] as? [String: Any]
    let currentCommand = current?["command"] as? String

    if currentCommand?.contains("ClaudeMonitorBridge") == true {
        var replacement = current ?? [:]
        replacement["type"] = "command"
        replacement["command"] = shellQuote(executable)
        settings["statusLine"] = replacement
        try writeJSONObject(settings, to: settingsURL)
        print("Updated Claude Monitor status-line bridge path.")
        return
    }

    let originalJSON = try current.map {
        try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
    }
    let config = BridgeConfig(
        originalStatusLineJSON: originalJSON,
        originalCommand: currentCommand
    )
    try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: configURL, options: .atomic)

    var replacement = current ?? [:]
    replacement["type"] = "command"
    replacement["command"] = shellQuote(executable)
    settings["statusLine"] = replacement
    try writeJSONObject(settings, to: settingsURL)
    print("Installed Claude Monitor status-line bridge in \(settingsURL.path).")
}

private func uninstall() throws {
    var settings = try readSettings()
    guard let current = settings["statusLine"] as? [String: Any],
          let command = current["command"] as? String,
          command.contains("ClaudeMonitorBridge") else {
        print("Claude Monitor does not own the current status-line setting; nothing changed.")
        return
    }

    let config = try? JSONDecoder().decode(BridgeConfig.self, from: Data(contentsOf: configURL))
    if let data = config?.originalStatusLineJSON,
       let original = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
        settings["statusLine"] = original
    } else {
        settings.removeValue(forKey: "statusLine")
    }
    try writeJSONObject(settings, to: settingsURL)
    print("Removed Claude Monitor status-line bridge.")
}

private func forwardToOriginal(_ command: String, input: Data) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardInput = pipe
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    do {
        try process.run()
        pipe.fileHandleForWriting.write(input)
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        FileHandle.standardError.write(Data("Claude Monitor could not run the previous status line: \(error)\n".utf8))
        return 1
    }
}

do {
    if CommandLine.arguments.contains("--install") {
        try install()
        exit(0)
    }
    if CommandLine.arguments.contains("--uninstall") {
        try uninstall()
        exit(0)
    }

    let input = FileHandle.standardInput.readDataToEndOfFile()
    var usage: Usage?
    do {
        usage = try UsageCache.usage(fromStatusLine: input)
        if let usage { try UsageCache.write(usage) }
    } catch {
        usage = nil
        if ProcessInfo.processInfo.environment["CLAUDEMON_DEBUG"] != nil {
            FileHandle.standardError.write(Data("Claude Monitor cache update skipped: \(error)\n".utf8))
        }
    }

    if let config = try? JSONDecoder().decode(BridgeConfig.self, from: Data(contentsOf: configURL)),
       let command = config.originalCommand, !command.isEmpty {
        exit(forwardToOriginal(command, input: input))
    }

    if let usage {
        var parts = ["5h: \(usage.sessionPercent)%"]
        if let week = usage.weekPercent { parts.append("7d: \(week)%") }
        print("[Claude] " + parts.joined(separator: "  "))
    }
} catch {
    FileHandle.standardError.write(Data("Claude Monitor status-line bridge: \(error)\n".utf8))
    exit(1)
}

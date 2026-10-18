import Foundation

enum CommandKind: String, Codable, CaseIterable, Identifiable {
    case script, shell
    var id: String { rawValue }
    var title: String { self == .script ? tr("Script file", "脚本文件") : tr("Shell command", "Shell 命令") }
}

struct ToolCommand: Codable, Equatable {
    var kind: CommandKind = .script
    var value: String = ""
    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct ToolDefinition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var workingDirectory: String = ""
    var start: ToolCommand = ToolCommand()
    var end: ToolCommand = ToolCommand()
    var openURL: String = ""
    var isPinned: Bool = false
}

extension ToolDefinition {
    private enum CodingKeys: String, CodingKey {
        case id, name, workingDirectory, start, end, openURL, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        start = try container.decode(ToolCommand.self, forKey: .start)
        end = try container.decode(ToolCommand.self, forKey: .end)
        openURL = try container.decode(String.self, forKey: .openURL)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

enum ToolPhase: String {
    case idle, running, stopping, external, failed
    var title: String {
        switch self {
        case .idle: return tr("Ready", "就绪")
        case .running: return tr("Running", "运行中")
        case .stopping: return tr("Stopping", "正在停止")
        case .external: return tr("Start command finished", "启动命令已完成")
        case .failed: return tr("Needs attention", "需要检查")
        }
    }
}

struct ToolRuntimeState {
    var phase: ToolPhase = .idle
    var detail: String = ""
    var pid: Int32? = nil
}

struct LauncherError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum AppPaths {
    static var dataDirectory: URL {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
            return URL(fileURLWithPath: args[index + 1], isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MungTools", isDirectory: true)
    }
}

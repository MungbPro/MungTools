import Foundation
import Combine
import Darwin

@MainActor
final class ToolManager: ObservableObject {
    @Published private(set) var tools: [ToolDefinition] = []
    @Published private(set) var states: [UUID: ToolRuntimeState] = [:]
    @Published var errorMessage: String?
    @Published var isQuitting = false

    let dataDirectory: URL

    private struct Configuration: Codable {
        var version: Int = 1
        var tools: [ToolDefinition]
    }

    private final class Execution {
        let process: Process
        let token: UUID
        let log: FileHandle
        init(process: Process, token: UUID, log: FileHandle) {
            self.process = process
            self.token = token
            self.log = log
        }
    }

    private var starts: [UUID: Execution] = [:]
    private var ends: [UUID: Execution] = [:]
    private var requestedStops: [UUID: UUID] = [:]
    private var forcedTokens: Set<UUID> = []
    private var stopFailures: [UUID: String] = [:]
    private var externalSessions: Set<UUID> = []
    private var damagedConfiguration = false
    private let stopTimeout: UInt64 = 8_000_000_000
    private var configurationURL: URL { dataDirectory.appendingPathComponent("tools.json") }
    private var logsDirectory: URL { dataDirectory.appendingPathComponent("logs", isDirectory: true) }

    init(dataDirectory: URL = AppPaths.dataDirectory) {
        self.dataDirectory = dataDirectory.standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: self.dataDirectory, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: configurationURL.path) else { return }
            let decoded = try Self.decodeConfiguration(Data(contentsOf: configurationURL))
            var seen = Set<UUID>()
            guard decoded.tools.allSatisfy({ seen.insert($0.id).inserted }) else {
                throw LauncherError(tr("The configuration contains duplicate tool IDs.", "配置中包含重复的工具 ID。"))
            }
            tools = decoded.tools
        } catch {
            damagedConfiguration = FileManager.default.fileExists(atPath: configurationURL.path)
            errorMessage = tr("Could not read the configuration. The original file has been preserved: \(error.localizedDescription)\n\(configurationURL.path)\nIt will be backed up before you save again.", "无法读取配置，原文件已保留：\(error.localizedDescription)\n\(configurationURL.path)\n再次保存前会先创建备份。")
        }
    }

    func state(for id: UUID) -> ToolRuntimeState { states[id] ?? ToolRuntimeState() }

    var hasActiveTasks: Bool {
        starts.values.contains { $0.process.isRunning } || ends.values.contains { $0.process.isRunning }
    }

    var sessionToolIDs: Set<UUID> {
        Set(tools.filter {
            // Process.isRunning can become false before its MainActor exit
            // callback runs. Keep that Start in this session until the callback
            // retires it, so an immediate quit cannot skip its Stop command.
            starts[$0.id] != nil || hasExecution(for: $0.id) ||
                (externalSessions.contains($0.id) && !$0.end.isEmpty)
        }.map(\.id))
    }

    var hasSessionToolsToStop: Bool { !sessionToolIDs.isEmpty }

    func save(_ tool: ToolDefinition) throws {
        guard !hasExecution(for: tool.id) else { throw LauncherError(tr("Stop this tool before editing its settings.", "请先停止此工具，再编辑设置。")) }
        let normalized = try validate(tool)
        var updated = tools
        if let index = updated.firstIndex(where: { $0.id == tool.id }) {
            updated[index] = normalized
        } else {
            updated.append(normalized)
        }
        try persist(updated)
        tools = updated
    }

    func setPinned(_ id: UUID, _ pinned: Bool) throws {
        guard let index = tools.firstIndex(where: { $0.id == id }) else {
            throw LauncherError(tr("This tool no longer exists.", "此工具已不存在。"))
        }
        guard tools[index].isPinned != pinned else { return }
        var updated = tools
        updated[index].isPinned = pinned
        // Pinning changes organization only. It must remain available while a
        // tool is running, even if its scripts or working directory have moved.
        try persist(updated)
        tools = updated
    }

    func delete(_ id: UUID) throws {
        guard !hasExecution(for: id) else { throw LauncherError(tr("This tool is still running or stopping. Stop it before deleting it.", "此工具仍在运行或停止中，请先停止后再删除。")) }
        let updated = tools.filter { $0.id != id }
        try persist(updated)
        tools = updated
        states.removeValue(forKey: id)
        stopFailures.removeValue(forKey: id)
        externalSessions.remove(id)
    }

    func export(to url: URL) throws {
        try configurationData(tools).write(to: url, options: .atomic)
    }

    @discardableResult
    func importTools(from url: URL) throws -> Int {
        let isImportDocument = url.pathExtension.lowercased() == ToolImportSupport.fileExtension
        if isImportDocument { try ToolImportSupport.validateDocumentURL(url) }
        let incoming = try Self.decodeConfiguration(Data(contentsOf: url))
        var updated = tools
        var seen = Set(tools.map(\.id))
        for item in incoming.tools {
            var normalized = try validate(item)
            if isImportDocument {
                if let existing = updated.first(where: { $0.id == normalized.id }) {
                    guard existing == normalized else {
                        throw LauncherError(tr("The import reuses an existing tool ID with different settings: \(normalized.name). Nothing was imported. Use a new UUID for a new tool.", "导入文件重复使用了已有工具 ID，但设置不同：\(normalized.name)。未导入任何内容。新工具请使用新的 UUID。"))
                    }
                    continue
                }
                // A regenerated file may use fresh UUIDs. Do not add another
                // identical tool just because its generated identity changed.
                if updated.contains(where: { existing in
                    var sameIdentity = normalized
                    sameIdentity.id = existing.id
                    return existing == sameIdentity
                }) { continue }
            }
            while seen.contains(normalized.id) { normalized.id = UUID() }
            seen.insert(normalized.id)
            updated.append(normalized)
        }
        let added = updated.count - tools.count
        guard added > 0 else { return 0 }
        try persist(updated)
        tools = updated
        return added
    }

    func logURL(for id: UUID) -> URL { logsDirectory.appendingPathComponent("\(id.uuidString).log") }

    func logText(for id: UUID) -> String {
        guard let handle = try? FileHandle(forReadingFrom: logURL(for: id)) else { return tr("No logs yet.", "暂无日志。") }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            if size > 65_536 { try handle.seek(toOffset: size - 65_536) }
            else { try handle.seek(toOffset: 0) }
            return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        } catch { return tr("Could not read the log: \(error.localizedDescription)", "无法读取日志：\(error.localizedDescription)") }
    }

    func start(_ id: UUID) {
        guard !isQuitting else {
            errorMessage = tr("Mung Tools is stopping tools and quitting. Cancel quit before starting a tool.", "工具箱正在停止工具并退出。请先取消退出，再启动工具。")
            return
        }
        guard let tool = tools.first(where: { $0.id == id }) else { return }
        guard !hasExecution(for: id) else {
            errorMessage = tr("This tool still has a process started by Mung Tools. Stop it before starting again.", "此工具仍有由工具箱启动的进程，请先停止后再启动。")
            return
        }
        // A process can finish before its MainActor callback is delivered. Retire
        // those executions now so their callbacks cannot change a new run.
        if let previous = starts.removeValue(forKey: id) {
            appendExit(previous, status: previous.process.terminationStatus, reason: previous.process.terminationReason)
            forcedTokens.remove(previous.token)
        }
        if let previous = ends.removeValue(forKey: id) {
            appendExit(previous, status: previous.process.terminationStatus, reason: previous.process.terminationReason)
            forcedTokens.remove(previous.token)
        }
        requestedStops.removeValue(forKey: id)
        stopFailures.removeValue(forKey: id)
        do {
            let normalized = try validate(tool)
            let execution = try launch(normalized.start, tool: normalized, label: tr("START", "启动"), rotate: true) { [weak self] token, status, reason in
                self?.startFinished(id: id, token: token, status: status, reason: reason)
            }
            starts[id] = execution
            states[id] = ToolRuntimeState(phase: .running, detail: tr("The start process is running.", "启动进程正在运行。"), pid: execution.process.processIdentifier)
        } catch { fail(id, tr("Could not start: \(error.localizedDescription)", "无法启动：\(error.localizedDescription)")) }
    }

    func stop(_ id: UUID) {
        guard let tool = tools.first(where: { $0.id == id }) else { return }
        guard ends[id]?.process.isRunning != true else { return }
        if !tool.end.isEmpty {
            do {
                let normalized = try validate(tool, includeStart: false)
                let execution = try launch(normalized.end, tool: normalized, label: tr("END", "停止"), rotate: !hasExecution(for: id)) { [weak self] token, status, reason in
                    self?.endFinished(id: id, token: token, status: status, reason: reason)
                }
                ends[id] = execution
                stopFailures.removeValue(forKey: id)
                states[id] = ToolRuntimeState(phase: .stopping, detail: tr("Running the custom stop command.", "正在执行自定义停止命令。"), pid: runningStartPID(id) ?? execution.process.processIdentifier)
            } catch {
                let message = tr("Could not run the stop command: \(error.localizedDescription)", "无法执行停止命令：\(error.localizedDescription)")
                stopFailures[id] = message
                fail(id, message)
            }
        } else if let entry = starts[id], entry.process.isRunning {
            requestTermination(id, execution: entry)
        } else {
            states[id] = ToolRuntimeState(phase: .idle, detail: tr("No process started by Mung Tools is still running.", "没有仍在运行的工具箱进程。"))
        }
    }

    func forceStop(_ id: UUID) {
        var didSignal = false
        if let entry = ends[id], entry.process.isRunning {
            forcedTokens.insert(entry.token)
            didSignal = signal(entry, ownedBy: ends[id], value: SIGKILL) || didSignal
        }
        if let entry = starts[id], entry.process.isRunning {
            requestedStops[id] = entry.token
            forcedTokens.insert(entry.token)
            didSignal = signal(entry, ownedBy: starts[id], value: SIGKILL) || didSignal
        }
        if didSignal {
            stopFailures.removeValue(forKey: id)
            states[id] = ToolRuntimeState(phase: .stopping, detail: tr("Sent a force stop signal to processes started by Mung Tools.", "已向工具箱启动的进程发送强制停止信号。"), pid: runningStartPID(id) ?? runningEndPID(id))
        } else if !hasExecution(for: id) {
            states[id] = ToolRuntimeState(phase: .idle, detail: tr("No process started by Mung Tools is still running.", "没有仍在运行的工具箱进程。"))
        } else {
            fail(id, tr("Could not verify process ownership. No force stop signal was sent.", "无法确认进程归属，未发送强制停止信号。"))
        }
    }

    func stopAll() {
        let targets = sessionToolIDs
        for tool in tools where targets.contains(tool.id) {
            stop(tool.id)
        }
    }

    private func hasExecution(for id: UUID) -> Bool {
        starts[id]?.process.isRunning == true || ends[id]?.process.isRunning == true
    }

    private func runningStartPID(_ id: UUID) -> Int32? {
        guard let entry = starts[id], entry.process.isRunning else { return nil }
        return entry.process.processIdentifier
    }

    private func runningEndPID(_ id: UUID) -> Int32? {
        guard let entry = ends[id], entry.process.isRunning else { return nil }
        return entry.process.processIdentifier
    }

    private func validate(_ original: ToolDefinition, includeStart: Bool = true) throws -> ToolDefinition {
        var tool = original
        tool.name = tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tool.name.isEmpty else { throw LauncherError(tr("Enter a tool name.", "请输入工具名称。")) }
        if includeStart, tool.start.isEmpty { throw LauncherError(tr("Choose a start script or enter a start command.", "请选择启动脚本或输入启动命令。")) }
        let directory = tool.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = directory.isEmpty ? NSHomeDirectory() : (directory as NSString).expandingTildeInPath
        let directoryURL = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LauncherError(tr("The working directory does not exist: \(directoryURL.path)", "工作目录不存在：\(directoryURL.path)"))
        }
        tool.workingDirectory = directoryURL.path
        let commands = includeStart ? [tool.start, tool.end] : [tool.end]
        for command in commands where command.kind == .script && !command.isEmpty {
            _ = try scriptURL(command, directory: directoryURL)
        }
        return tool
    }

    private func scriptURL(_ command: ToolCommand, directory: URL) throws -> URL {
        let path = (command.value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw LauncherError(tr("Script file not found: \(url.path)", "找不到脚本文件：\(url.path)"))
        }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw LauncherError(tr("The script is not executable: \(url.path)\nAdd execute permission in Terminal before running it. Mung Tools leaves the original script unchanged.", "脚本没有执行权限：\(url.path)\n请先在终端中添加执行权限。工具箱不会修改原脚本。"))
        }
        return url.standardizedFileURL
    }

    private func launch(_ command: ToolCommand, tool: ToolDefinition, label: String, rotate: Bool,
                        onExit: @escaping @MainActor (UUID, Int32, Process.TerminationReason) -> Void) throws -> Execution {
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let url = logURL(for: tool.id)
        if rotate, let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber, size.intValue >= 10 * 1024 * 1024 {
            let previous = url.appendingPathExtension("1")
            if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
            try FileManager.default.moveItem(at: url, to: previous)
        }
        // Start and End may write concurrently. O_APPEND is required so the
        // two independent file descriptors cannot overwrite each other's logs.
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard descriptor >= 0 else {
            throw LauncherError(tr("Could not open the log file: \(url.path) (\(String(cString: strerror(errno))))", "无法打开日志文件：\(url.path)（\(String(cString: strerror(errno)))）"))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.seekToEnd()
            let header = "\n[\(ISO8601DateFormatter().string(from: Date()))] \(label) \(tool.name)\n"
            try handle.write(contentsOf: Data(header.utf8))
            let process = Process()
            let cwd = URL(fileURLWithPath: tool.workingDirectory, isDirectory: true)
            if command.kind == .script {
                process.executableURL = try scriptURL(command, directory: cwd)
                process.arguments = []
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command.value]
            }
            process.currentDirectoryURL = cwd
            var environment = ProcessInfo.processInfo.environment
            let paths = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] + (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            var seen = Set<String>()
            environment["PATH"] = paths.filter { seen.insert($0).inserted }.joined(separator: ":")
            environment["PYTHONUNBUFFERED"] = "1"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = handle
            process.standardError = handle
            let token = UUID()
            process.terminationHandler = { terminated in
                let status = terminated.terminationStatus
                let reason = terminated.terminationReason
                Task { @MainActor in onExit(token, status, reason) }
            }
            do { try process.run() }
            catch { throw LauncherError(tr("\(error.localizedDescription)\nScripts need a valid shebang on the first line, such as #!/bin/zsh.", "\(error.localizedDescription)\n脚本第一行需要有效的解释器声明，例如 #!/bin/zsh。")) }
            return Execution(process: process, token: token, log: handle)
        } catch {
            try? handle.write(contentsOf: Data((tr("[Launch error]", "[启动错误]") + " \(error.localizedDescription)\n").utf8))
            try? handle.close()
            throw error
        }
    }

    private func startFinished(id: UUID, token: UUID, status: Int32, reason: Process.TerminationReason) {
        guard let entry = starts[id], entry.token == token else { return }
        appendExit(entry, status: status, reason: reason)
        starts.removeValue(forKey: id)
        let wasRequested = requestedStops[id] == token
        if wasRequested { requestedStops.removeValue(forKey: id) }
        forcedTokens.remove(token)
        if wasRequested { externalSessions.remove(id) }
        else if status == 0 && reason == .exit { externalSessions.insert(id) }
        if let stop = ends[id], stop.process.isRunning {
            states[id] = ToolRuntimeState(phase: .stopping, detail: tr("The start process has exited. Waiting for the stop command to finish.", "启动进程已退出，正在等待停止命令完成。"), pid: stop.process.processIdentifier)
        } else if let message = stopFailures[id] {
            fail(id, message)
        } else if wasRequested {
            states[id] = ToolRuntimeState(phase: .idle, detail: tr("The process started by Mung Tools has stopped.", "工具箱启动的进程已停止。"))
        } else if status == 0 && reason == .exit {
            states[id] = ToolRuntimeState(phase: .external, detail: tr("The start command has finished. Open the tool to check whether its service is running in the background. You can run its stop command.", "启动命令已完成。请打开工具确认服务是否在后台运行；现在可以执行停止命令。"))
        } else {
            fail(id, tr("The start process \(exitDescription(status, reason)). Check the log for details.", "启动进程\(exitDescription(status, reason))。请查看日志了解详情。"))
        }
    }

    private func endFinished(id: UUID, token: UUID, status: Int32, reason: Process.TerminationReason) {
        guard let entry = ends[id], entry.token == token else { return }
        appendExit(entry, status: status, reason: reason)
        ends.removeValue(forKey: id)
        let wasForced = forcedTokens.remove(token) != nil
        if wasForced {
            if let start = starts[id], start.process.isRunning {
                states[id] = ToolRuntimeState(phase: .stopping, detail: tr("The stop command was force stopped. Waiting for the start process to exit.", "停止命令已被强制终止，正在等待启动进程退出。"), pid: start.process.processIdentifier)
            } else { states[id] = ToolRuntimeState(phase: .idle, detail: tr("Processes started by Mung Tools have been force stopped.", "工具箱启动的进程已被强制停止。")) }
        } else if status == 0 && reason == .exit {
            stopFailures.removeValue(forKey: id)
            externalSessions.remove(id)
            if let start = starts[id] {
                // Remember success even if Start has exited and its callback is
                // still queued; that callback must not restore external state.
                requestedStops[id] = start.token
                if start.process.isRunning { requestTermination(id, execution: start) }
                else { states[id] = ToolRuntimeState(phase: .idle, detail: tr("The stop command has finished.", "停止命令已完成。")) }
            } else { states[id] = ToolRuntimeState(phase: .idle, detail: tr("The stop command has finished.", "停止命令已完成。")) }
        } else {
            let message = tr("The stop command \(exitDescription(status, reason)). Check the log, then try stopping again.", "停止命令\(exitDescription(status, reason))。请查看日志后重试。")
            stopFailures[id] = message
            fail(id, message)
        }
    }

    private func requestTermination(_ id: UUID, execution: Execution) {
        requestedStops[id] = execution.token
        guard signal(execution, ownedBy: starts[id], value: SIGTERM) else {
            let message = tr("Could not verify process ownership. No stop signal was sent.", "无法确认进程归属，未发送停止信号。")
            stopFailures[id] = message
            fail(id, message)
            return
        }
        stopFailures.removeValue(forKey: id)
        states[id] = ToolRuntimeState(phase: .stopping, detail: tr("Stop signal sent. Waiting for the process to exit.", "已发送停止信号，正在等待进程退出。"), pid: execution.process.processIdentifier)
        let token = execution.token
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.stopTimeout)
            guard self.starts[id]?.token == token, self.starts[id]?.process.isRunning == true,
                  self.requestedStops[id] == token, self.ends[id]?.process.isRunning != true else { return }
            self.states[id] = ToolRuntimeState(phase: .stopping, detail: tr("The process has not exited. Use Force Stop if you need to end it now.", "进程尚未退出。如需立即结束，请使用“强制停止”。"), pid: self.starts[id]?.process.processIdentifier)
        }
    }

    private func signal(_ entry: Execution, ownedBy current: Execution?, value: Int32) -> Bool {
        guard let current, current === entry, entry.process.isRunning else { return false }
        let pid = entry.process.processIdentifier
        guard pid > 1, getpgid(pid) == pid else { return false }
        return Darwin.kill(-pid, value) == 0
    }

    private func appendExit(_ entry: Execution, status: Int32, reason: Process.TerminationReason) {
        try? entry.log.write(contentsOf: Data(tr("[Process \(exitDescription(status, reason))]\n", "[进程\(exitDescription(status, reason))]\n").utf8))
        try? entry.log.close()
    }

    private func exitDescription(_ status: Int32, _ reason: Process.TerminationReason) -> String {
        reason == .exit ? tr("exited with code \(status)", "已退出，退出码 \(status)") : tr("was terminated by signal \(status)", "已被信号 \(status) 终止")
    }

    private func fail(_ id: UUID, _ message: String) {
        states[id] = ToolRuntimeState(phase: .failed, detail: message, pid: runningStartPID(id) ?? runningEndPID(id))
        errorMessage = message
    }

    private static func decodeConfiguration(_ data: Data) throws -> Configuration {
        let decoder = JSONDecoder()
        if let configuration = try? decoder.decode(Configuration.self, from: data) {
            guard configuration.version == 1 else { throw LauncherError(tr("Unsupported configuration version: \(configuration.version).", "不支持此配置版本：\(configuration.version)。")) }
            return configuration
        }
        return Configuration(tools: try decoder.decode([ToolDefinition].self, from: data))
    }

    private func configurationData(_ items: [ToolDefinition]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Configuration(tools: items))
    }

    private func persist(_ updated: [ToolDefinition]) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        if damagedConfiguration, FileManager.default.fileExists(atPath: configurationURL.path) {
            let backup = dataDirectory.appendingPathComponent("tools.corrupt-\(UUID().uuidString).json")
            do { try FileManager.default.copyItem(at: configurationURL, to: backup) }
            catch { throw LauncherError(tr("Could not back up the damaged configuration. Nothing was saved: \(error.localizedDescription)", "无法备份损坏的配置，未保存任何更改：\(error.localizedDescription)")) }
        }
        try configurationData(updated).write(to: configurationURL, options: .atomic)
        damagedConfiguration = false
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
    }
}

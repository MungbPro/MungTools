import Foundation
import Darwin

@MainActor
enum LauncherSelfTests {
    static func wait(_ seconds: Double = 5, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw LauncherError("Timed out waiting for a test condition") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    static func run() async -> Int32 {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("MungTools-test-\(UUID().uuidString)")
        var manager: ToolManager?
        let sentinel = Process()
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ title: String) throws {
            guard value() else { throw LauncherError("FAIL: \(title)") }
            count += 1
            print("PASS \(count): \(title)")
        }
        func script(_ name: String, _ body: String, mode: Int = 0o700) throws -> URL {
            let path = root.appendingPathComponent(name)
            try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path.path)
            return path
        }
        func importFile(_ name: String, _ tools: [ToolDefinition]) throws -> URL {
            let path = root.appendingPathComponent(name)
            let objects = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tools))
            try JSONSerialization.data(withJSONObject: ["version": 1, "tools": objects], options: [.prettyPrinted])
                .write(to: path)
            return path
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let languageSuite = "pro.mungb.tool-launcher.self-test.\(UUID().uuidString)"
            let languageDefaults = UserDefaults(suiteName: languageSuite)!
            defer { languageDefaults.removePersistentDomain(forName: languageSuite) }
            let preferences = AppPreferences(defaults: languageDefaults)
            try check(preferences.language == .english, "New installations use English until the user chooses a language")
            preferences.language = .simplifiedChinese
            try check(AppPreferences(defaults: languageDefaults).language == .simplifiedChinese,
                      "The selected Simplified Chinese interface survives reopening")
            preferences.language = .english
            try check(AppPreferences(defaults: languageDefaults).language == .english,
                      "Switching back to English is persisted")
            try check(AppLanguage.english.appName == "Mung Tools" &&
                      AppLanguage.simplifiedChinese.appName == "熊梦白 AI 工具箱" &&
                      AppLanguage.english.creatorLinkTitle == "More About Mung" &&
                      AppLanguage.simplifiedChinese.creatorLinkTitle == "关注我-熊梦白",
                      "Both languages use the requested app name and creator label")
            let cwdPointer = realpath(root.path, nil)!
            let canonicalCWD = String(cString: cwdPointer)
            free(cwdPointer)
            let data = root.appendingPathComponent("settings")
            let store = ToolManager(dataDirectory: data)
            manager = store
            let fixture = try script("中文 工具's.command", "printf 'OUT=%s\\n' \"$PWD\"; echo STDERR_OK >&2; /bin/sleep 60 &\necho $! > child.pid\nwait")
            let original = try Data(contentsOf: fixture)
            let tool = ToolDefinition(name: "  测试工具  ", workingDirectory: root.path,
                start: ToolCommand(kind: .script, value: fixture.path))
            try store.save(tool)
            try check(store.tools.first?.name == "测试工具", "Tool names are trimmed and configuration is saved atomically")
            var legacyObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool)) as! [String: Any]
            legacyObject.removeValue(forKey: "isPinned")
            let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
            let legacyTool = try JSONDecoder().decode(ToolDefinition.self, from: legacyData)
            try check(!legacyTool.isPinned && legacyTool.id == tool.id, "Legacy tools without a pin flag decode as unpinned")
            let legacyDirectory = root.appendingPathComponent("legacy-settings")
            try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
            let legacyConfiguration = legacyDirectory.appendingPathComponent("tools.json")
            try JSONSerialization.data(withJSONObject: ["version": 1, "tools": [legacyObject]]).write(to: legacyConfiguration)
            let legacyWrappedStore = ToolManager(dataDirectory: legacyDirectory)
            try check(legacyWrappedStore.errorMessage == nil && legacyWrappedStore.tools.first?.isPinned == false,
                      "Legacy versioned configurations remain readable")
            try JSONSerialization.data(withJSONObject: [legacyObject]).write(to: legacyConfiguration)
            let legacyArrayStore = ToolManager(dataDirectory: legacyDirectory)
            try check(legacyArrayStore.errorMessage == nil && legacyArrayStore.tools.first?.isPinned == false,
                      "Legacy array configurations remain readable")
            try store.setPinned(tool.id, true)
            let reloaded = ToolManager(dataDirectory: data)
            try check(reloaded.tools.count == 1 && reloaded.state(for: tool.id).pid == nil, "Reopening keeps settings without adopting historical PIDs")
            try check(reloaded.tools.first?.isPinned == true, "Pinned tools stay pinned after reopening")
            let exported = root.appendingPathComponent("export.json")
            try store.export(to: exported); try store.importTools(from: exported)
            try check(store.tools.count == 2 && Set(store.tools.map(\.id)).count == 2, "Export and import preserve tools while assigning duplicate IDs fresh identities")
            try check(store.tools.allSatisfy(\.isPinned), "Export and import preserve pinned flags with distinct IDs")
            try store.delete(store.tools.last!.id)
            try store.setPinned(tool.id, false)
            try check(ToolManager(dataDirectory: data).tools.first?.isPinned == false, "Unpinning is persisted")

            let importsDirectory = root.appendingPathComponent("import-settings")
            let imports = ToolManager(dataDirectory: importsDirectory)
            let existingImportTool = ToolDefinition(name: "Already saved", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "exit 0"))
            try imports.save(existingImportTool)
            let importMarker = root.appendingPathComponent("MUST_NOT_IMPORT_RUN")
            let importedTool = ToolDefinition(name: "Imported without running", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "touch MUST_NOT_IMPORT_RUN"),
                end: ToolCommand(kind: .shell, value: "touch MUST_NOT_IMPORT_RUN"))
            let importURL = try importFile("import.MUNGTOOLS", [importedTool])
            try ToolImportSupport.validateDocumentURL(importURL)
            let wrongExtension = try importFile("wrong.txt", [importedTool])
            var wrongExtensionRejected = false
            do { try ToolImportSupport.validateDocumentURL(wrongExtension) } catch { wrongExtensionRejected = true }
            let fakeDocument = root.appendingPathComponent("directory.mungtools")
            try FileManager.default.createDirectory(at: fakeDocument, withIntermediateDirectories: true)
            var directoryRejected = false
            do { try ToolImportSupport.validateDocumentURL(fakeDocument) } catch { directoryRejected = true }
            try check(wrongExtensionRejected && directoryRejected,
                      "Document imports require a regular .mungtools file and accept uppercase extensions")
            let importCount = try imports.importTools(from: importURL)
            try check(importCount == 1 && imports.tools == [existingImportTool, importedTool] &&
                      !imports.hasActiveTasks && !FileManager.default.fileExists(atPath: importMarker.path),
                      "Import adds tools without replacing existing tools or executing Start or End")
            let repeatedCount = try imports.importTools(from: importURL)
            try check(repeatedCount == 0 && imports.tools.count == 2,
                      "Reopening the same .mungtools file is idempotent")
            var regeneratedTool = importedTool
            regeneratedTool.id = UUID()
            let regeneratedURL = try importFile("regenerated.mungtools", [regeneratedTool])
            let regeneratedCount = try imports.importTools(from: regeneratedURL)
            try check(regeneratedCount == 0 && imports.tools.count == 2,
                      "Regenerated IDs do not duplicate identical imported tools")
            let importConfiguration = importsDirectory.appendingPathComponent("tools.json")
            let importBeforeFailure = try Data(contentsOf: importConfiguration)
            let importToolsBeforeFailure = imports.tools
            let validExtra = ToolDefinition(name: "Valid in rejected batch", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "touch MUST_NOT_IMPORT_RUN"))
            let invalidExtra = ToolDefinition(name: "Invalid in rejected batch", workingDirectory: root.path,
                start: ToolCommand(kind: .script, value: root.appendingPathComponent("missing.command").path))
            let invalidBatch = try importFile("invalid-batch.mungtools", [validExtra, invalidExtra])
            var batchRejected = false
            do { try imports.importTools(from: invalidBatch) } catch { batchRejected = true }
            let importAfterFailure = try Data(contentsOf: importConfiguration)
            try check(batchRejected && importAfterFailure == importBeforeFailure && imports.tools == importToolsBeforeFailure,
                      "A failed import leaves both memory and the saved configuration unchanged")
            var conflictingTool = importedTool
            conflictingTool.name = "Changed settings with a reused UUID"
            let conflictingURL = try importFile("conflicting.mungtools", [validExtra, conflictingTool])
            var conflictRejected = false
            do { try imports.importTools(from: conflictingURL) } catch { conflictRejected = true }
            let importAfterConflict = try Data(contentsOf: importConfiguration)
            try check(conflictRejected && importAfterConflict == importBeforeFailure && imports.tools == importToolsBeforeFailure,
                      "A conflicting UUID rejects the whole import without overwriting existing settings")
            let malformedImport = root.appendingPathComponent("malformed.mungtools")
            try Data("{invalid".utf8).write(to: malformedImport)
            var malformedRejected = false
            do { try imports.importTools(from: malformedImport) } catch { malformedRejected = true }
            try check(malformedRejected && imports.tools == importToolsBeforeFailure &&
                      !FileManager.default.fileExists(atPath: importMarker.path),
                      "Malformed imports preserve saved tools and never execute commands")
            sentinel.executableURL = URL(fileURLWithPath: "/bin/sleep")
            sentinel.arguments = ["60"]
            try sentinel.run()
            store.start(tool.id)
            try await wait { FileManager.default.fileExists(atPath: root.appendingPathComponent("child.pid").path) }
            let pid = store.state(for: tool.id).pid!
            let child = Int32(try String(contentsOf: root.appendingPathComponent("child.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
            try check(getpgid(pid) == pid && getpgid(child) == pid, "Managed commands and their children share an isolated process group")
            try check(store.logText(for: tool.id).contains("OUT=\(canonicalCWD)") && store.logText(for: tool.id).contains("STDERR_OK"), "Unicode, spaces, and quotes in script paths preserve cwd and stdout/stderr")
            store.start(tool.id)
            try check(store.state(for: tool.id).pid == pid, "Duplicate starts are rejected")
            let runtimeBeforeImport = store.state(for: tool.id)
            let sessionBeforeImport = store.sessionToolIDs
            try store.importTools(from: importURL)
            try check(store.state(for: tool.id).pid == runtimeBeforeImport.pid &&
                      store.state(for: tool.id).phase == runtimeBeforeImport.phase &&
                      store.state(for: tool.id).detail == runtimeBeforeImport.detail &&
                      store.sessionToolIDs == sessionBeforeImport &&
                      !FileManager.default.fileExists(atPath: importMarker.path),
                      "Importing while a tool runs preserves its process, runtime state, and session membership")
            var deletionRejected = false
            do { try store.delete(tool.id) } catch is LauncherError { deletionRejected = true }
            try check(deletionRejected, "Running tools cannot be deleted")
            store.errorMessage = nil
            store.stop(tool.id)
            try await wait { store.state(for: tool.id).phase == .idle }
            try check(!store.hasActiveTasks && sentinel.isRunning, "Stopping a managed process group leaves unrelated processes running")
            // The parent is gone, and child no longer has a live process group.
            try await wait { getpgid(child) != pid || kill(child, 0) != 0 }
            let sourceAfterRun = try Data(contentsOf: fixture)
            try check(sourceAfterRun == original, "Original scripts are not moved or changed")

            let pinDirectory = root.appendingPathComponent("pin-fixtures")
            let movedPinDirectory = root.appendingPathComponent("pin-fixtures-moved")
            try FileManager.default.createDirectory(at: pinDirectory, withIntermediateDirectories: true)
            let pinScript = try script("pin-fixtures/Start.command", "echo PIN_READY; exec /bin/sleep 60")
            let pinTool = ToolDefinition(name: "Pin while running", workingDirectory: pinDirectory.path,
                start: ToolCommand(kind: .script, value: pinScript.path))
            try store.save(pinTool); store.start(pinTool.id)
            try await wait { store.logText(for: pinTool.id).contains("PIN_READY") }
            let pinState = store.state(for: pinTool.id)
            let logBeforePin = store.logText(for: pinTool.id)
            try FileManager.default.moveItem(at: pinDirectory, to: movedPinDirectory)
            try store.setPinned(pinTool.id, true)
            var expectedPinnedTool = pinTool
            expectedPinnedTool.isPinned = true
            try check(store.tools.first(where: { $0.id == pinTool.id }) == expectedPinnedTool &&
                      store.state(for: pinTool.id).pid == pinState.pid &&
                      store.state(for: pinTool.id).phase == pinState.phase &&
                      store.state(for: pinTool.id).detail == pinState.detail &&
                      store.logText(for: pinTool.id) == logBeforePin,
                      "Pinning a running tool with missing scripts changes only its saved pin flag")
            try store.setPinned(pinTool.id, false)
            try check(store.tools.first(where: { $0.id == pinTool.id }) == pinTool &&
                      store.state(for: pinTool.id).pid == pinState.pid &&
                      ToolManager(dataDirectory: data).tools.first(where: { $0.id == pinTool.id })?.isPinned == false,
                      "Unpinning a running tool preserves its process and all tool settings")
            store.stop(pinTool.id)
            try await wait { store.state(for: pinTool.id).phase == .idle }

            let shell = ToolDefinition(name: "自定义命令", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "print SHELL_OK; if read value; then exit 9; else print STDIN_EOF; fi"))
            try store.save(shell); store.start(shell.id)
            try await wait { store.state(for: shell.id).phase == .external }
            try check(store.logText(for: shell.id).contains("SHELL_OK") && store.logText(for: shell.id).contains("STDIN_EOF"), "Custom zsh commands receive noninteractive stdin")
            try check(store.state(for: shell.id).pid == nil, "A successful script exit reports command completion without a managed PID")

            let bad = ToolDefinition(name: "失败命令", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "echo EXPECTED_FAILURE >&2; exit 7"))
            try store.save(bad); store.start(bad.id)
            try await wait { store.state(for: bad.id).phase == .failed }
            try check(store.state(for: bad.id).detail.contains("7") && store.logText(for: bad.id).contains("EXPECTED_FAILURE"), "Failed commands expose their exit code and error logs")
            store.errorMessage = nil

            let large = ToolDefinition(name: "大量日志", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "i=0; while (( i < 4000 )); do print 'large-log-abcdefghijklmnopqrstuvwxyz0123456789'; (( i++ )); done; exit 0"))
            try store.save(large); store.start(large.id)
            try await wait { store.state(for: large.id).phase == .external }
            try check(store.logText(for: large.id).utf8.count <= 65_539, "Large output does not block and the UI reads only the log tail")

            let gone = try script("moved.command", "exit 0")
            let endMarker = root.appendingPathComponent("end.marker")
            let endScript = try script("end.command", "touch end.marker")
            let external = ToolDefinition(name: "外部工具停止", workingDirectory: root.path,
                start: ToolCommand(kind: .script, value: gone.path), end: ToolCommand(kind: .script, value: endScript.path))
            try store.save(external)
            try FileManager.default.removeItem(at: gone)
            store.stop(external.id)
            try await wait { FileManager.default.fileExists(atPath: endMarker.path) && store.state(for: external.id).phase == .idle }
            try check(true, "Stop commands work without a managed Start and with a missing Start script")

            let stubborn = try script("stubborn.command", "trap '' TERM\nwhile :; do /bin/sleep 1; done")
            let stubbornTool = ToolDefinition(name: "停止失败与强停", workingDirectory: root.path,
                start: ToolCommand(kind: .script, value: stubborn.path), end: ToolCommand(kind: .shell, value: "exit 9"))
            try store.save(stubbornTool); store.start(stubbornTool.id)
            try await Task.sleep(nanoseconds: 100_000_000)
            store.stop(stubbornTool.id)
            try await wait { store.state(for: stubbornTool.id).phase == .failed }
            try check(store.state(for: stubbornTool.id).pid != nil, "A failed Stop retains the managed process for explicit force stopping")
            store.errorMessage = nil
            store.forceStop(stubbornTool.id)
            try await wait { store.state(for: stubbornTool.id).phase == .idle }
            try check(sentinel.isRunning, "Force Stop affects only a process group held by this session")

            let raceScript = try script("race.command", "if [ -f once.marker ]; then /bin/sleep 30; else touch once.marker; fi")
            let race = ToolDefinition(name: "快速重新启动", workingDirectory: root.path,
                start: ToolCommand(kind: .script, value: raceScript.path))
            try store.save(race); store.start(race.id)
            usleep(250_000) // Deliberately defer old exit callback on main actor.
            store.start(race.id)
            try await Task.sleep(nanoseconds: 100_000_000)
            try check(store.state(for: race.id).phase == .running && store.state(for: race.id).pid != nil, "A stale exit callback cannot overwrite a newer run")
            store.stop(race.id)
            try await wait { store.state(for: race.id).phase == .idle }

            let pendingExit = ToolDefinition(name: "Pending exit callback", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "exit 0"),
                end: ToolCommand(kind: .shell, value: "touch pending-end.marker"))
            try store.save(pendingExit); store.start(pendingExit.id)
            // Intentionally hold the MainActor until the OS process exits,
            // leaving startFinished queued while Stop All is requested.
            let pendingDeadline = Date().addingTimeInterval(5)
            while store.hasActiveTasks && Date() < pendingDeadline { usleep(20_000) }
            try check(!store.hasActiveTasks && store.state(for: pendingExit.id).phase == .running,
                      "Start exited while its MainActor callback is still queued")
            store.stopAll()
            try await wait {
                FileManager.default.fileExists(atPath: root.appendingPathComponent("pending-end.marker").path) &&
                    store.state(for: pendingExit.id).phase == .idle
            }
            try check(!store.sessionToolIDs.contains(pendingExit.id),
                      "Stop All runs End before a pending Start exit callback can drop the session")

            let backgroundStart = try script("background.command", "/bin/sleep 20 > detached.log 2>&1 &\necho $! > detached.pid\nexit 0")
            var background = ToolDefinition(name: "后台服务", workingDirectory: root.path,
                start: ToolCommand(kind: .script, value: backgroundStart.path),
                end: ToolCommand(kind: .shell, value: "exit 7"))
            try store.save(background); store.start(background.id)
            try await wait { store.state(for: background.id).phase == .external }
            try check(store.state(for: background.id).pid == nil && store.sessionToolIDs.contains(background.id), "Detached services retain Stop management without claiming a managed PID")
            store.stop(background.id)
            try await wait { store.state(for: background.id).phase == .failed }
            try check(store.hasSessionToolsToStop && store.sessionToolIDs.contains(background.id), "A detached service remains pending after a failed Stop")
            store.errorMessage = nil
            background.end = ToolCommand(kind: .shell, value: "/bin/kill -TERM \"$(cat detached.pid)\"; print END_OK")
            try store.save(background)
            let unused = ToolDefinition(name: "未启动工具", workingDirectory: root.path,
                start: ToolCommand(kind: .shell, value: "exit 0"),
                end: ToolCommand(kind: .shell, value: "touch UNUSED_END"))
            try store.save(unused)
            store.stopAll()
            try await wait { store.state(for: background.id).phase == .idle }
            try check(!store.sessionToolIDs.contains(background.id) && !FileManager.default.fileExists(atPath: root.appendingPathComponent("UNUSED_END").path), "Stop All retries failed session stops and ignores never-started tools")
            store.isQuitting = true
            store.start(shell.id)
            try check(!store.hasActiveTasks, "New starts are blocked while quitting")
            store.isQuitting = false
            store.errorMessage = nil

            let noPermission = try script("not-executable.command", "exit 0", mode: 0o600)
            do {
                try store.save(ToolDefinition(name: "不可执行", workingDirectory: root.path, start: ToolCommand(kind: .script, value: noPermission.path)))
                throw NSError(domain: "Test", code: 1)
            } catch is LauncherError { try check(!FileManager.default.isExecutableFile(atPath: noPermission.path), "Nonexecutable scripts are rejected without changing permissions") }

            let brokenDir = root.appendingPathComponent("broken")
            try FileManager.default.createDirectory(at: brokenDir, withIntermediateDirectories: true)
            try Data("{invalid".utf8).write(to: brokenDir.appendingPathComponent("tools.json"))
            let broken = ToolManager(dataDirectory: brokenDir)
            try check(broken.errorMessage != nil, "Damaged configurations surface an error and preserve the original file")
            try broken.save(shell)
            let backup = try FileManager.default.contentsOfDirectory(at: brokenDir, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("tools.corrupt-") }
            let backupContents = try backup.map { try Data(contentsOf: $0) }
            try check(backupContents == Data("{invalid".utf8), "Recovering a damaged configuration first creates an identical backup")
            try check(!store.hasActiveTasks, "No managed tasks remain after testing")
            if sentinel.isRunning { sentinel.terminate(); sentinel.waitUntilExit() }
            try FileManager.default.removeItem(at: root)
            print("\(count) checks passed. No user tools were started or stopped.")
            return 0
        } catch {
            print("SELF-TEST FAILED: \(error.localizedDescription)\nFixtures retained at \(root.path)")
            manager?.tools.forEach { manager?.forceStop($0.id) }
            if sentinel.isRunning { sentinel.terminate(); sentinel.waitUntilExit() }
            return 1
        }
    }
}

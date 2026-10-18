import AppKit
import SwiftUI
import Combine

@MainActor
final class LauncherAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let manager = ToolManager(dataDirectory: AppPaths.dataDirectory)
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var managerWindow: NSWindow?
    private var allowTermination = false
    private var quitTimer: Timer?
    private var quitStarted = Date()
    private var quitTargets: Set<UUID> = []
    private var instanceLock: FileHandle?
    private var pendingImportURLs: [URL] = []
    private var hasFinishedLaunching = false
    private var isForwardingInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: manager.dataDirectory, withIntermediateDirectories: true)
            let lockURL = manager.dataDirectory.appendingPathComponent("app.lock")
            if !FileManager.default.fileExists(atPath: lockURL.path) {
                FileManager.default.createFile(atPath: lockURL.path, contents: Data())
            }
            instanceLock = try FileHandle(forUpdating: lockURL)
            guard flock(instanceLock!.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                isForwardingInstance = true
                let other = NSRunningApplication.runningApplications(withBundleIdentifier: "pro.mungb.tool-launcher")
                    .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                other?.activate(options: [.activateAllWindows])
                forwardImports(pendingImportURLs)
                pendingImportURLs.removeAll()
                allowTermination = true
                NSApp.terminate(nil)
                return
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("Cannot open tool settings", "无法打开工具设置")
            alert.informativeText = tr("Launch cancelled to avoid conflicting instances.\n\(error.localizedDescription)", "为避免多个实例覆盖配置，已取消启动。\n\(error.localizedDescription)")
            alert.runModal()
            allowTermination = true
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenManager(_:)),
            name: Notification.Name("pro.mungb.tool-launcher.showManager"),
            object: manager.dataDirectory.standardizedFileURL.path)
        NotificationCenter.default.addObserver(self, selector: #selector(collapseManager(_:)),
            name: Notification.Name("MungToolsCollapse"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshInterfaceLanguage(_:)),
            name: .mungToolsLanguageDidChange, object: nil)
        installMainMenu()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: AppLanguage.current.appName) {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = tr("Tools", "工具")
        }
        statusItem.button?.toolTip = tr("Mung Tools · Click to open or collapse · Right-click for tools", "熊梦白 AI 工具箱 · 点击展开或收起 · 右键打开工具菜单")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        hasFinishedLaunching = true
        showManager(nil)
        if !pendingImportURLs.isEmpty {
            let urls = pendingImportURLs
            pendingImportURLs.removeAll()
            importDocuments(urls)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if isForwardingInstance {
            forwardImports(urls)
            sender.reply(toOpenOrPrint: .success)
        } else if hasFinishedLaunching {
            sender.reply(toOpenOrPrint: importDocuments(urls) ? .success : .failure)
        } else {
            // LaunchServices may deliver documents before didFinishLaunching.
            // Wait until this instance owns its settings lock and has a window.
            pendingImportURLs.append(contentsOf: urls)
            sender.reply(toOpenOrPrint: .success)
        }
    }

    private func forwardImports(_ urls: [URL]) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("pro.mungb.tool-launcher.showManager"),
            object: manager.dataDirectory.standardizedFileURL.path,
            userInfo: urls.isEmpty ? nil : ["importPaths": urls.map(\.path)], deliverImmediately: true)
    }

    @discardableResult
    private func importDocuments(_ urls: [URL]) -> Bool {
        var failures: [String] = []
        var added = 0
        var imported = false
        for url in urls {
            do {
                guard !manager.isQuitting else {
                    throw LauncherError(tr("Cancel quit before importing tools.", "请先取消退出，再导入工具。"))
                }
                try ToolImportSupport.validateDocumentURL(url)
                added += try manager.importTools(from: url)
                imported = true
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { manager.errorMessage = failures.joined(separator: "\n\n") }
        showManager(nil)
        if imported {
            NotificationCenter.default.post(name: .mungToolsImported, object: manager,
                userInfo: ["addedCount": added])
        }
        return failures.isEmpty
    }

    @objc private func refreshInterfaceLanguage(_ notification: Notification) {
        installMainMenu()
        managerWindow?.title = AppLanguage.current.appName
        statusItem?.button?.toolTip = tr("Mung Tools · Click to open or collapse · Right-click for tools", "熊梦白 AI 工具箱 · 点击展开或收起 · 右键打开工具菜单")
        statusItem?.button?.setAccessibilityLabel(AppLanguage.current.appName)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: AppLanguage.current.appName)
        appMenu.addItem(item(tr("Open Mung Tools…", "打开熊梦白 AI 工具箱…"), #selector(showManager(_:)), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item(tr("Collapse to Menu Bar", "收起到菜单栏"), #selector(collapseManager(_:)), key: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(item(tr("Quit Mung Tools", "退出熊梦白 AI 工具箱"), #selector(quitApp(_:)), key: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: tr("Edit", "编辑"))
        editMenu.addItem(withTitle: tr("Undo", "撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: tr("Redo", "重做"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: tr("Cut", "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: tr("Copy", "复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("Paste", "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: tr("Select All", "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: tr("Window", "窗口"))
        windowMenu.addItem(item(tr("Collapse to Menu Bar", "收起到菜单栏"), #selector(collapseManager(_:))))
        windowMenu.addItem(withTitle: tr("Close Window", "关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if managerWindow?.isVisible == true && !NSApp.isHidden {
            menu.addItem(item(tr("Collapse to Menu Bar", "收起到菜单栏"), #selector(collapseManager(_:)), key: "h"))
        } else {
            menu.addItem(item(tr("Open Mung Tools…", "打开熊梦白 AI 工具箱…"), #selector(showManager(_:)), key: ","))
        }
        menu.addItem(.separator())
        if manager.tools.isEmpty {
            let empty = NSMenuItem(title: tr("No tools yet. Add your first tool.", "还没有工具，请先添加。"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        let orderedTools = manager.tools.filter(\.isPinned) + manager.tools.filter { !$0.isPinned }
        for tool in orderedTools {
            let state = manager.state(for: tool.id)
            let entry = NSMenuItem(title: "\(tool.name) · \(state.phase.title)", action: nil, keyEquivalent: "")
            if tool.isPinned {
                let pinImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: tr("Pinned", "已置顶"))
                pinImage?.isTemplate = true
                entry.image = pinImage
            }
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            let start = item(tr("Start", "启动"), #selector(startTool(_:)), id: tool.id)
            start.isEnabled = !manager.isQuitting && !manager.sessionToolIDs.contains(tool.id) && state.pid == nil && state.phase != .stopping
            submenu.addItem(start)
            let stop = item(tr("Stop", "停止"), #selector(stopTool(_:)), id: tool.id)
            stop.isEnabled = !manager.isQuitting && manager.sessionToolIDs.contains(tool.id) && state.phase != .stopping
            submenu.addItem(stop)
            if state.pid != nil {
                submenu.addItem(item(tr("Force Stop Managed Process…", "强制停止托管进程…"), #selector(forceStopTool(_:)), id: tool.id))
            }
            if !tool.openURL.isEmpty {
                submenu.addItem(.separator())
                submenu.addItem(item(tr("Open in Browser", "在浏览器中打开"), #selector(openToolURL(_:)), id: tool.id))
            }
            submenu.addItem(item(tr("View Logs", "查看日志"), #selector(revealToolLog(_:)), id: tool.id))
            submenu.addItem(.separator())
            let pin = item(tool.isPinned ? tr("Unpin Tool", "取消置顶") : tr("Pin Tool", "置顶工具"), #selector(togglePinnedTool(_:)), id: tool.id)
            pin.isEnabled = !manager.isQuitting
            submenu.addItem(pin)
            entry.submenu = submenu
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let languageItem = NSMenuItem(title: tr("Language", "语言"), action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for language in AppLanguage.allCases {
            let choice = NSMenuItem(title: language.displayName, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = language.rawValue
            choice.state = language == AppLanguage.current ? .on : .off
            languages.addItem(choice)
        }
        languageItem.submenu = languages
        menu.addItem(languageItem)
        menu.addItem(item(tr("Quit Mung Tools…", "退出熊梦白 AI 工具箱…"), #selector(quitApp(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, id: UUID? = nil, key: String = "") -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
        value.target = self
        value.representedObject = id?.uuidString
        return value
    }

    private func identifier(_ item: NSMenuItem) -> UUID? {
        (item.representedObject as? String).flatMap(UUID.init(uuidString:))
    }

    @objc private func reopenManager(_ notification: Notification) {
        if let paths = notification.userInfo?["importPaths"] as? [String], !paths.isEmpty {
            importDocuments(paths.map { URL(fileURLWithPath: $0).standardizedFileURL })
        } else {
            showManager(nil)
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else if managerWindow?.isVisible == true && !NSApp.isHidden {
            collapseManager(nil)
        } else {
            showManager(nil)
        }
    }

    @objc private func collapseManager(_ sender: Any?) {
        managerWindow?.orderOut(nil)
    }

    @objc func showManager(_ sender: Any?) {
        if managerWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = AppLanguage.current.appName
            window.minSize = NSSize(width: 760, height: 520)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.122, alpha: 1)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.contentView = NSHostingView(rootView: ManagerView(manager: manager).ignoresSafeArea())
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            managerWindow = window
        }
        managerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: Notification.Name("MungToolsFocusSearch"), object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager(nil)
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let language = AppLanguage(rawValue: value) else { return }
        AppPreferences.shared.language = language
    }

    @objc private func togglePinnedTool(_ sender: NSMenuItem) {
        guard let id = identifier(sender), let tool = manager.tools.first(where: { $0.id == id }) else { return }
        do { try manager.setPinned(id, !tool.isPinned) }
        catch { manager.errorMessage = error.localizedDescription; showManager(nil) }
    }

    @objc private func startTool(_ sender: NSMenuItem) { if let id = identifier(sender) { manager.start(id) } }
    @objc private func stopTool(_ sender: NSMenuItem) { if let id = identifier(sender) { manager.stop(id) } }
    @objc private func openToolURL(_ sender: NSMenuItem) {
        guard let id = identifier(sender), let tool = manager.tools.first(where: { $0.id == id }),
              let url = URL(string: tool.openURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func revealToolLog(_ sender: NSMenuItem) {
        guard let id = identifier(sender) else { return }
        let path = manager.logURL(for: id)
        if FileManager.default.fileExists(atPath: path.path) { NSWorkspace.shared.open(path) }
        else { showManager(nil) }
    }
    @objc private func forceStopTool(_ sender: NSMenuItem) {
        guard let id = identifier(sender) else { return }
        let alert = NSAlert()
        alert.messageText = tr("Force stop this tool?", "强制停止这个工具？")
        alert.informativeText = tr("This ends the process started by Mung Tools in this session. Unsaved work may be lost.", "这会结束本次由工具箱启动的进程。尚未保存的工作可能丢失。")
        alert.addButton(withTitle: tr("Cancel", "取消"))
        alert.addButton(withTitle: tr("Force Stop", "强制停止"))
        if alert.runModal() == .alertSecondButtonReturn { manager.forceStop(id) }
    }
    @objc private func quitApp(_ sender: Any?) { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTermination { return .terminateNow }
        if quitTimer != nil { return .terminateCancel }
        quitTargets = manager.sessionToolIDs
        guard manager.hasSessionToolsToStop else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = tr("Stop session tools and quit?", "停止本次工具并退出？")
        alert.informativeText = tr("Closing the window keeps Mung Tools in the menu bar. Quitting will first run Stop for tools started in this session.", "关闭窗口后，工具箱会保留在菜单栏。退出前会先停止本次启动的工具。")
        alert.addButton(withTitle: tr("Cancel", "取消"))
        alert.addButton(withTitle: tr("Stop and Quit", "停止并退出"))
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        manager.isQuitting = true
        manager.stopAll()
        quitStarted = Date()
        quitTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkQuitProgress() }
        }
        return .terminateCancel
    }

    private func checkQuitProgress() {
        let callbacksPending = quitTargets.contains {
            let state = manager.state(for: $0)
            return state.pid != nil || state.phase == .stopping
        }
        if !manager.hasActiveTasks && !callbacksPending {
            quitTimer?.invalidate(); quitTimer = nil
            let failures = quitTargets.contains { manager.state(for: $0).phase == .failed }
            if failures {
                let alert = NSAlert()
                alert.messageText = tr("Some Stop commands failed", "部分停止命令执行失败")
                alert.informativeText = tr("Check the tool logs for details. You can also quit and leave those tools running.", "请查看工具日志了解详情。也可以退出工具箱，让这些工具继续运行。")
                alert.addButton(withTitle: tr("Back to Tools", "返回工具箱"))
                alert.addButton(withTitle: tr("Quit Anyway", "仍然退出"))
                if alert.runModal() != .alertSecondButtonReturn {
                    manager.isQuitting = false
                    showManager(nil)
                    return
                }
            }
            allowTermination = true
            NSApp.terminate(nil)
        } else if Date().timeIntervalSince(quitStarted) > 10 {
            quitTimer?.invalidate(); quitTimer = nil
            let alert = NSAlert()
            alert.messageText = tr("Tools are still stopping", "工具仍在停止")
            alert.informativeText = tr("Return to the tools to keep waiting, or force stop processes managed in this session and quit.", "可以返回工具箱继续等待，或强制停止本次托管的进程后退出。")
            alert.addButton(withTitle: tr("Back to Tools", "返回工具箱"))
            alert.addButton(withTitle: tr("Force Stop and Quit", "强制停止并退出"))
            if alert.runModal() == .alertSecondButtonReturn {
                quitTargets.formUnion(manager.sessionToolIDs)
                for id in quitTargets { manager.forceStop(id) }
                quitStarted = Date()
                quitTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkQuitProgress() }
                }
            } else {
                manager.isQuitting = false
                showManager(nil)
            }
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    Task { @MainActor in
        let result = await LauncherSelfTests.run()
        exit(result)
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        let delegate = LauncherAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

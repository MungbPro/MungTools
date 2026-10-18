import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum LauncherPage: Equatable {
    case palette
    case importer
    case editor(UUID)
    case logs(UUID)
}

private enum LauncherFocus: Hashable { case search, name }
private enum PrimaryToolAction { case edit, logs, website, start }

private func launcherScriptURL(_ value: String, workingDirectory: String) -> URL {
    let path = NSString(string: value.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
    if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
    let directory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    let expandedDirectory = directory.isEmpty ? NSHomeDirectory() : NSString(string: directory).expandingTildeInPath
    return URL(fileURLWithPath: expandedDirectory, isDirectory: true).appendingPathComponent(path).standardizedFileURL
}

private enum PaletteStyle {
    static let background = Color(red: 28 / 255, green: 28 / 255, blue: 31 / 255)
    static let raised = Color(red: 37 / 255, green: 37 / 255, blue: 41 / 255)
    static let border = Color.white.opacity(0.10)
    static let muted = Color(red: 151 / 255, green: 151 / 255, blue: 160 / 255)
    static let selection = Color.white.opacity(0.07)
}

private struct ToolAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String = ""
    var enabled = true
    var destructive = false
    let perform: () -> Void
}

struct ManagerView: View {
    @ObservedObject var manager: ToolManager
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var page: LauncherPage = .palette
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var drafts: [UUID: ToolDefinition] = [:]
    @State private var actionsOpen = false
    @State private var actionIndex = 0
    @State private var logText = ""
    @State private var deleteCandidate: ToolDefinition?
    @State private var forceCandidate: ToolDefinition?
    @State private var promptCopied = false
    @FocusState private var focusedField: LauncherFocus?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var allTools: [ToolDefinition] {
        let saved = manager.tools.map { drafts[$0.id] ?? $0 }
        let extra = drafts.values.filter { draft in !manager.tools.contains(where: { $0.id == draft.id }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return saved + extra
    }

    private var filteredTools: [ToolDefinition] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = allTools.filter { tool in
            needle.isEmpty || [tool.name, tool.workingDirectory, tool.start.value, tool.end.value]
                .joined(separator: " ").localizedCaseInsensitiveContains(needle)
        }
        return matching.filter(\.isPinned) + matching.filter { !$0.isPinned }
    }

    private var pinnedResults: [ToolDefinition] { filteredTools.filter(\.isPinned) }
    private var otherResults: [ToolDefinition] { filteredTools.filter { !$0.isPinned } }

    private var selectedTool: ToolDefinition? { selectedID.flatMap(tool) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) { pageContent }
            if actionsOpen { actionOverlay }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(PaletteStyle.background)
        .preferredColorScheme(.dark)
        .tint(.cyan)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PaletteStyle.border, lineWidth: 1))
        .background(LauncherKeyboardHandler(handle: handleKey).frame(width: 0, height: 0))
        .onAppear { ensureSelection(); focusSearch() }
        .onChange(of: query) { _, _ in ensureSelection() }
        .onChange(of: manager.tools) { _, _ in syncDraftPins(); ensureSelection() }
        .onReceive(timer) { _ in if case .logs = page { refreshLog() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MungToolsFocusSearch"))) { _ in
            if page == .palette { focusSearch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MungToolsImported"))) { _ in
            query = ""
            if page == .importer { backToPalette() }
        }
        .onChange(of: preferences.language) { _, _ in promptCopied = false }
        .alert(tr("Something needs attention", "需要处理的问题"), isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button(tr("OK", "好"), role: .cancel) { manager.errorMessage = nil }
        } message: { Text(manager.errorMessage ?? "") }
        .confirmationDialog(tr("Delete \(deleteCandidate?.name ?? "this tool")?", "删除\(deleteCandidate?.name ?? "此工具")？"), isPresented: Binding(
            get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            Button(tr("Delete Configuration", "删除配置"), role: .destructive, action: deleteTool)
            Button(tr("Cancel", "取消"), role: .cancel) { deleteCandidate = nil }
        } message: { Text(tr("This removes the saved configuration. Your original scripts and project files stay in place.", "这将删除已保存的配置。原始脚本和项目文件会保留。")) }
        .alert(tr("Force stop \(forceCandidate?.name ?? "this tool")?", "强制停止\(forceCandidate?.name ?? "此工具")？"), isPresented: Binding(
            get: { forceCandidate != nil }, set: { if !$0 { forceCandidate = nil } }
        )) {
            Button(tr("Cancel", "取消"), role: .cancel) { forceCandidate = nil }
            Button(tr("Force Stop", "强制停止"), role: .destructive) {
                if let tool = forceCandidate { manager.forceStop(tool.id) }
                forceCandidate = nil
            }
        } message: { Text(tr("Immediately end the processes started by Mung Tools. Unsaved work in those processes may be lost.", "立即结束由工具箱启动的进程。这些进程中尚未保存的内容可能会丢失。")) }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .palette:
            searchBar
            separator
            paletteResults
            separator
            paletteFooter
        case .editor(let id): editorPage(id)
        case .logs(let id): logsPage(id)
        case .importer: importPage
        }
    }

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").font(.system(size: 19, weight: .medium))
                .foregroundStyle(PaletteStyle.muted)
            TextField(tr("Search tools or commands…", "搜索工具或命令…"), text: $query)
                .font(.system(size: 19, weight: .regular)).textFieldStyle(.plain)
                .focused($focusedField, equals: .search).accessibilityIdentifier("tool-search")
            if !query.isEmpty {
                Button { query = ""; focusSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(PaletteStyle.muted)
                }.buttonStyle(.plain).help(tr("Clear search · Esc", "清空搜索 · Esc"))
            }
            languagePicker
            creatorBranding
            collapseButton
        }.padding(.horizontal, 24).frame(height: 72)
    }

    private var paletteResults: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if filteredTools.isEmpty { emptyResults }
                else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(filteredTools.enumerated()), id: \.element.id) { index, item in
                                    if index == 0 || filteredTools[index - 1].isPinned != item.isPinned {
                                        resultHeader(for: item)
                                    }
                                    toolRow(item).id(item.id)
                                }
                            }.padding(.horizontal, 8).padding(.bottom, 12)
                        }
                        .onChange(of: selectedID) { _, id in
                            if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
                        }
                    }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let item = selectedTool, !filteredTools.isEmpty {
                Rectangle().fill(PaletteStyle.border).frame(width: 1)
                toolSummary(item).frame(width: 267).frame(maxHeight: .infinity, alignment: .top)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultHeader(for item: ToolDefinition) -> some View {
        let title = item.isPinned ? tr("PINNED", "已置顶") : (pinnedResults.isEmpty ? (query.isEmpty ? tr("YOUR TOOLS", "我的工具") : tr("RESULTS", "搜索结果")) : tr("OTHER TOOLS", "其他工具"))
        let count = item.isPinned ? pinnedResults.count : otherResults.count
        return HStack {
            sectionLabel(title)
            Spacer()
            Text("\(count)").font(.system(size: 11)).foregroundStyle(PaletteStyle.muted)
        }.padding(.horizontal, 8).padding(.top, 17).padding(.bottom, 6)
    }

    private func toolRow(_ item: ToolDefinition) -> some View {
        let state = manager.state(for: item.id)
        let selected = item.id == selectedID
        return HStack(spacing: 0) {
            Button { selectedID = item.id; focusSearch() } label: {
                HStack(spacing: 11) {
                    toolIcon(item, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name.isEmpty ? tr("Untitled Tool", "未命名工具") : item.name)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        Text(subtitle(item)).font(.system(size: 11)).foregroundStyle(PaletteStyle.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isDirty(item) {
                        Text(tr("DRAFT", "草稿")).font(.system(size: 9, weight: .medium)).foregroundStyle(.orange.opacity(0.9))
                    } else { Circle().fill(phaseColor(state.phase)).frame(width: 6, height: 6) }
                }
                .padding(.leading, 11).padding(.trailing, 5).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name.isEmpty ? tr("Untitled Tool", "未命名工具") : item.name)
            .accessibilityHint(tr("Select tool. Press Return for \(primaryTitle(item)).", "选择工具。按回车键\(primaryTitle(item))。"))
            Button { togglePin(item) } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.isPinned ? Color.cyan : PaletteStyle.muted.opacity(0.7))
                    .frame(width: 30, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.trailing, 5)
            .disabled(!isSaved(item.id) || manager.isQuitting)
            .help(isSaved(item.id) ? "\(item.isPinned ? tr("Unpin Tool", "取消置顶") : tr("Pin Tool", "置顶工具")) · ⌘P" : tr("Save the tool before pinning it", "保存工具后即可置顶"))
            .accessibilityLabel("\(item.isPinned ? tr("Unpin", "取消置顶") : tr("Pin", "置顶")) \(item.name.isEmpty ? tr("Untitled Tool", "未命名工具") : item.name)")
            .accessibilityIdentifier("pin-tool-\(item.id.uuidString)")
        }
        .background(selected ? PaletteStyle.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contextMenu {
            ForEach(actions(for: item)) { action in
                Button(role: action.destructive ? .destructive : nil, action: action.perform) {
                    Label(action.title, systemImage: action.symbol)
                }.disabled(!action.enabled)
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 13) {
            Image(systemName: query.isEmpty ? "square.stack.3d.up" : "magnifyingglass")
                .font(.system(size: 30, weight: .light)).foregroundStyle(PaletteStyle.muted)
            Text(query.isEmpty ? tr("Your tools, one place.", "所有工具，集中管理。") : tr("No matching tools", "没有匹配的工具"))
                .font(.system(size: 17, weight: .medium))
            Text(query.isEmpty ? tr("Let Codex find and add your tools.", "让 Codex 帮你查找并添加工具。") : tr("Try another search or import a tool.", "试试其他关键词，或导入工具。"))
                .font(.system(size: 12)).foregroundStyle(PaletteStyle.muted)
            Button(tr("Import Tools", "导入工具"), action: showImport)
                .buttonStyle(.bordered).padding(.top, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toolSummary(_ item: ToolDefinition) -> some View {
        let state = manager.state(for: item.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    toolIcon(item, size: 44)
                    Text(item.name.isEmpty ? tr("Untitled Tool", "未命名工具") : item.name)
                        .font(.system(size: 18, weight: .semibold)).lineLimit(3)
                    HStack(spacing: 6) {
                        Circle().fill(isDirty(item) ? .orange : phaseColor(state.phase)).frame(width: 6, height: 6)
                        Text(isDirty(item) ? tr("Unsaved draft", "未保存的草稿") : state.phase.title).font(.system(size: 11))
                            .foregroundStyle(PaletteStyle.muted)
                    }
                    if item.isPinned {
                        Label(tr("Pinned", "已置顶"), systemImage: "pin.fill").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.cyan).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.10)).clipShape(Capsule())
                    }
                }
                toolControls(item)
                separator
                summaryValue(tr("START", "启动"), value: commandSummary(item.start), symbol: "play")
                summaryValue(tr("END", "结束"), value: item.end.isEmpty ? tr("Stop managed process", "停止托管进程") : commandSummary(item.end), symbol: "stop")
                if !item.workingDirectory.isEmpty {
                    summaryValue(tr("WORKING DIRECTORY", "工作目录"), value: shortPath(item.workingDirectory), symbol: "folder")
                }
                if !item.openURL.isEmpty { summaryValue(tr("WEBSITE", "网页"), value: item.openURL, symbol: "globe") }
                if state.phase == .external {
                    Text(tr("The start command finished. The tool may still be running in another app or in the background.", "启动命令已完成。工具可能仍在其他应用或后台运行。"))
                        .font(.system(size: 11)).foregroundStyle(PaletteStyle.muted).lineSpacing(3)
                } else if !state.detail.isEmpty {
                    Text(state.detail).font(.system(size: 11)).foregroundStyle(PaletteStyle.muted).lineSpacing(3)
                        .textSelection(.enabled)
                }
                Button { editTool(item.id) } label: {
                    HStack { Image(systemName: "slider.horizontal.3"); Text(tr("Edit Tool", "编辑工具")); Spacer(); shortcut("⌘E") }
                        .font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(PaletteStyle.muted).disabled(isBusy(item.id))
            }.padding(22)
        }
    }

    private func toolControls(_ item: ToolDefinition) -> some View {
        let saved = savedTool(item.id)
        let canStart = canStartTool(item)
        let canEnd = canEndTool(item)
        return HStack(spacing: 9) {
            Button { if canStartTool(item) { manager.start(item.id) } } label: {
                Label(tr("Start", "启动"), systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .foregroundStyle(canStart ? Color.green : PaletteStyle.muted.opacity(0.65))
                    .background(canStart ? Color.green.opacity(0.17) : Color.white.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(canStart ? Color.green.opacity(0.3) : PaletteStyle.border))
            }
            .buttonStyle(.plain).disabled(!canStart)
            .help(isDirty(item) ? tr("Save your changes before starting the tool", "保存修改后即可启动工具") : tr("Run the tool's Start command", "执行工具的启动命令"))
            .accessibilityLabel(tr("Start \(item.name.isEmpty ? "Untitled Tool" : item.name)", "启动\(item.name.isEmpty ? "未命名工具" : item.name)"))
            Button { if canEndTool(item) { manager.stop(item.id) } } label: {
                Label(tr("End", "结束"), systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .foregroundStyle(canEnd ? Color.red : PaletteStyle.muted.opacity(0.65))
                    .background(canEnd ? Color.red.opacity(0.17) : Color.white.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(canEnd ? Color.red.opacity(0.3) : PaletteStyle.border))
            }
            .buttonStyle(.plain).disabled(!canEnd)
            .help(saved?.end.isEmpty ?? true ? tr("Stop the process started by Mung Tools", "停止由工具箱启动的进程") : tr("Run the tool's saved End command", "执行工具已保存的结束命令"))
            .accessibilityLabel(tr("End \(item.name.isEmpty ? "Untitled Tool" : item.name)", "结束\(item.name.isEmpty ? "未命名工具" : item.name)"))
        }
    }

    private func summaryValue(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel(title)
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: symbol).font(.system(size: 10)).frame(width: 13).padding(.top, 2)
                Text(value).font(.system(size: 11)).lineLimit(3).textSelection(.enabled)
            }.foregroundStyle(Color.white.opacity(0.76))
        }
    }

    private var paletteFooter: some View {
        HStack(spacing: 13) {
            Image(systemName: "terminal").font(.system(size: 13)).foregroundStyle(PaletteStyle.muted)
            Text(tr("Local tools", "本地工具")).font(.system(size: 11)).foregroundStyle(PaletteStyle.muted)
            Spacer()
            Button(action: showImport) {
                Label(tr("Import", "导入"), systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(.cyan)
                .disabled(manager.isQuitting).accessibilityIdentifier("import-tools")
            footerDivider
            Button(action: performPrimary) {
                HStack(spacing: 7) {
                    Text(selectedTool.map(primaryTitle) ?? tr("Select a Tool", "选择工具")).font(.system(size: 11, weight: .medium))
                    shortcut("↵")
                }
            }.buttonStyle(.plain).disabled(selectedTool == nil || primaryDisabled)
            footerDivider
            Button(action: toggleActions) {
                HStack(spacing: 7) { Text(tr("Actions", "操作")).font(.system(size: 11)); shortcut("⌘K") }
            }.buttonStyle(.plain)
            footerDivider
            Button(action: newTool) {
                HStack(spacing: 7) { Text(tr("New", "新建")).font(.system(size: 11)); shortcut("⌘N") }
            }.buttonStyle(.plain)
        }.padding(.horizontal, 18).frame(height: 48)
    }

    private var importPage: some View {
        VStack(spacing: 0) {
            pageHeader(title: tr("Import Tools", "导入工具"), subtitle: tr("TOOLS", "工具"))
            separator
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 23)).foregroundStyle(.cyan)
                                .frame(width: 44, height: 44).background(Color.cyan.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(tr("Let Codex do the setup", "让 Codex 帮你添加"))
                                    .font(.system(size: 19, weight: .semibold))
                                Text(tr("Copy a prompt. Paste it into Codex. Your tools appear here.", "复制提示词，粘贴到 Codex，工具就会添加到这里。"))
                                    .font(.system(size: 12)).foregroundStyle(PaletteStyle.muted)
                            }
                            Spacer(minLength: 8)
                            Text(tr("RECOMMENDED", "推荐")).font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.cyan).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.10)).clipShape(Capsule())
                        }
                        Text(tr("Find my local tools, pair their Start and End scripts, and add them to Mung Tools.", "查找我的本地工具，配对启动与结束脚本，并添加到熊梦白 AI 工具箱。"))
                            .font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .background(Color.black.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 9))
                        HStack(spacing: 14) {
                            Button(action: copyCodexPrompt) {
                                Label(promptCopied ? tr("Copied · Paste in Codex", "已复制 · 粘贴到 Codex") : tr("Copy Codex Prompt", "复制 Codex 提示词"),
                                      systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.black).padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.cyan).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                                .disabled(manager.isQuitting).accessibilityIdentifier("copy-codex-prompt")
                            Text(tr("Use Codex with access to your local project folders.", "请在有权访问本地项目文件夹的 Codex 中使用。"))
                                .font(.system(size: 11)).foregroundStyle(PaletteStyle.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(21).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cyan.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.18)))

                    HStack(spacing: 14) {
                        Image(systemName: "doc.badge.arrow.up").font(.system(size: 22)).foregroundStyle(PaletteStyle.muted)
                            .frame(width: 42)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Already have a configuration?", "已有配置文件？")).font(.system(size: 14, weight: .semibold))
                            Text(tr("Import a .mungtools or .json file yourself.", "手动导入 .mungtools 或 .json 文件。"))
                                .font(.system(size: 12)).foregroundStyle(PaletteStyle.muted)
                        }
                        Spacer()
                        Button(tr("Choose File…", "选择文件…"), action: importTools)
                            .buttonStyle(.bordered).disabled(manager.isQuitting).accessibilityIdentifier("choose-import-file")
                    }.padding(20).background(Color.white.opacity(0.025)).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PaletteStyle.border))
                    Button(tr("Or add a tool manually", "也可以手动新建工具"), action: newTool)
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(PaletteStyle.muted)
                }.padding(26)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            separator
            HStack {
                Label(tr("Nothing runs until you press Start.", "点击启动之前，不会执行任何命令。"), systemImage: "checkmark.shield")
                    .foregroundStyle(PaletteStyle.muted)
                Spacer()
                Button(action: backToPalette) { HStack { Text(tr("Back", "返回")); shortcut("Esc") } }.buttonStyle(.plain)
            }.font(.system(size: 11)).padding(.horizontal, 22).frame(height: 48)
        }
    }

    private func showImport() {
        actionsOpen = false
        focusedField = nil
        promptCopied = false
        page = .importer
    }

    private func copyCodexPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        promptCopied = pasteboard.setString(ToolImportSupport.codexPrompt(language: preferences.language), forType: .string)
    }

    @ViewBuilder private func editorPage(_ id: UUID) -> some View {
        if let item = tool(id) {
            let itemBinding = binding(for: id)
            let busy = isBusy(id)
            pageHeader(title: isSaved(id) ? tr("Edit Tool", "编辑工具") : tr("New Tool", "新建工具"), subtitle: tr("TOOLS", "工具"))
            separator
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    formField(tr("Name", "名称")) {
                        paletteTextField(tr("Tool name", "工具名称"), text: itemBinding.name).focused($focusedField, equals: .name)
                    }
                    LauncherCommandField(title: tr("Start", "启动"), subtitle: tr("Run when you launch the tool.", "启动工具时执行。"), command: itemBinding.start,
                                         workingDirectory: itemBinding.workingDirectory)
                    LauncherCommandField(title: tr("End", "结束"), subtitle: tr("Optional. Leave blank to stop the managed process.", "选填。留空时停止托管进程。"), command: itemBinding.end,
                                         workingDirectory: itemBinding.workingDirectory)
                    formField(tr("Working Directory", "工作目录")) {
                        HStack(spacing: 8) {
                            paletteTextField(tr("Defaults to your home folder", "默认为个人文件夹"), text: itemBinding.workingDirectory, monospaced: true)
                            Button { chooseDirectory(for: itemBinding) } label: { Image(systemName: "folder") }
                                .buttonStyle(.bordered).help(tr("Choose working directory", "选择工作目录"))
                        }
                    }
                    formField(tr("Website", "网页")) {
                        paletteTextField("http://localhost:8808", text: itemBinding.openURL, monospaced: true)
                    }
                    Text(tr("Scripts run from their original files. Changes here never modify your scripts.", "直接运行原始脚本文件。此处修改不会更改脚本内容。"))
                        .font(.system(size: 11)).foregroundStyle(PaletteStyle.muted).padding(.leading, 130)
                    if busy {
                        Text(tr("Stop the tool before editing its configuration.", "停止工具后即可编辑配置。")).font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }.padding(26).disabled(busy || manager.isQuitting)
            }
            separator
            HStack {
                Button(action: backToPalette) { HStack(spacing: 7) { Text(tr("Back", "返回")); shortcut("Esc") } }
                    .buttonStyle(.plain).foregroundStyle(PaletteStyle.muted)
                Spacer()
                if isDirty(item) { Text(tr("Unsaved draft", "未保存的草稿")).font(.system(size: 11)).foregroundStyle(PaletteStyle.muted) }
                Button { saveAndReturn(item) } label: {
                    HStack(spacing: 8) { Text(isSaved(id) ? tr("Save Changes", "保存修改") : tr("Create Tool", "创建工具")); shortcut("⌘↵") }
                        .font(.system(size: 12, weight: .medium))
                }.buttonStyle(.borderedProminent).tint(Color.white.opacity(0.16)).disabled(busy || manager.isQuitting)
            }.font(.system(size: 11)).padding(.horizontal, 22).frame(height: 52)
        } else { missingToolPage }
    }

    private func logsPage(_ id: UUID) -> some View {
        VStack(spacing: 0) {
            pageHeader(title: tool(id)?.name ?? tr("Tool Logs", "工具日志"), subtitle: tr("LOGS", "日志"))
            separator
            ScrollView([.vertical, .horizontal]) {
                Text(logText.isEmpty ? tr("No output yet. Start or stop the tool to see its logs here.", "暂无输出。启动或结束工具后，可在此查看日志。") : logText)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.8))
                    .textSelection(.enabled).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(22)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            separator
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(.green.opacity(0.8)).frame(width: 5, height: 5)
                    Text(tr("Last 64 KB · refreshes every second", "最近 64 KB · 每秒刷新"))
                }.font(.system(size: 11)).foregroundStyle(PaletteStyle.muted)
                Spacer()
                Button(tr("Reveal Log File", "在访达中显示日志")) { revealLog(id) }.buttonStyle(.plain)
                footerDivider
                Button(action: backToPalette) { HStack { Text(tr("Back", "返回")); shortcut("Esc") } }.buttonStyle(.plain)
            }.font(.system(size: 11)).padding(.horizontal, 22).frame(height: 48)
        }
    }

    private var missingToolPage: some View {
        VStack(spacing: 16) {
            Text(tr("This tool is no longer available.", "此工具已不存在。")).foregroundStyle(PaletteStyle.muted)
            Button(tr("Back to Tools", "返回工具列表"), action: backToPalette)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Button(action: backToPalette) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30).background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).help(tr("Back to tools · Esc", "返回工具列表 · Esc"))
            sectionLabel(subtitle)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(PaletteStyle.muted.opacity(0.6))
            Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1)
            Spacer()
            languagePicker
            creatorBranding
            collapseButton
        }.padding(.horizontal, 22).frame(height: 72)
    }

    private var languagePicker: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    preferences.language = language
                } label: {
                    if preferences.language == language {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PaletteStyle.muted)
                .frame(width: 28, height: 30)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(tr("Language", "语言"))
        .accessibilityLabel(tr("Change language", "切换语言"))
        .accessibilityIdentifier("language-picker")
    }

    private var creatorProfileURL: URL? {
        let value = Branding.creatorProfileURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(host),
              !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty else { return nil }
        return url
    }

    private var creatorBranding: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(preferences.language.appName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1)
            Button {
                if let url = creatorProfileURL { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 4) {
                    Text(preferences.language.creatorLinkTitle)
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.cyan.opacity(0.95))
            }
            .buttonStyle(.plain)
            .disabled(creatorProfileURL == nil)
            .help(creatorProfileURL == nil
                  ? tr("Creator's X profile will be added soon", "即将添加作者的 X 主页")
                  : tr("Visit Mung on X", "前往熊梦白的 X 主页"))
            .accessibilityIdentifier("creator-profile-link")
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private var collapseButton: some View {
        Button(action: collapseToMenuBar) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PaletteStyle.muted)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(tr("Close Window · ⌘H", "关闭窗口 · ⌘H"))
        .accessibilityLabel(tr("Close Window", "关闭窗口"))
        .accessibilityHint(tr("Hide this window and keep tools running. Click the menu bar icon to reopen.", "隐藏窗口，工具继续运行。点击菜单栏图标可重新打开。"))
        .accessibilityIdentifier("collapse-to-menu-bar")
    }

    private func collapseToMenuBar() {
        actionsOpen = false
        NotificationCenter.default.post(name: Notification.Name("MungToolsCollapse"), object: nil)
    }

    private var actionOverlay: some View {
        let items = currentActions
        return ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.14).contentShape(Rectangle()).onTapGesture { actionsOpen = false; focusSearch() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tr("Actions", "操作")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    shortcut("Esc")
                }.padding(14)
                separator
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, action in
                                actionRow(action, index: index).id(action.id)
                            }
                        }.padding(6)
                    }
                    .onChange(of: actionIndex) { _, index in
                        if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
                    }
                }
            }
            .frame(width: 290, height: min(CGFloat(items.count * 35 + 57), 416))
            .background(PaletteStyle.raised).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(PaletteStyle.border))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
            .padding(.trailing, 12).padding(.bottom, 56)
        }
    }

    private func actionRow(_ action: ToolAction, index: Int) -> some View {
        Button {
            actionsOpen = false
            action.perform()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.symbol).font(.system(size: 12)).frame(width: 16)
                Text(action.title).font(.system(size: 12))
                Spacer()
                if !action.shortcut.isEmpty { shortcut(action.shortcut) }
            }
            .foregroundStyle(action.destructive ? Color.red.opacity(0.9) : Color.white.opacity(action.enabled ? 0.9 : 0.3))
            .padding(.horizontal, 9).frame(height: 32)
            .background(actionIndex == index ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!action.enabled)
            .onHover { if $0 && action.enabled { actionIndex = index } }
    }

    private var currentActions: [ToolAction] { actions(for: selectedTool) }

    private func actions(for item: ToolDefinition?) -> [ToolAction] {
        var result: [ToolAction] = []
        if let item {
            let state = manager.state(for: item.id)
            let saved = savedTool(item.id)
            let busy = isBusy(item.id)
            result.append(ToolAction(id: "primary", title: primaryTitle(item), symbol: primarySymbol(item), shortcut: "↵", enabled: !primaryIsDisabled(item)) { performPrimary(item) })
            if state.phase == .external && !busy {
                result.append(ToolAction(id: "restart", title: tr("Run Start Again", "再次执行启动命令"), symbol: "arrow.clockwise",
                                         enabled: canStartTool(item)) { if canStartTool(item) { manager.start(item.id) } })
            }
            result.append(ToolAction(id: "stop", title: tr("Stop Tool", "结束工具"), symbol: "stop", shortcut: "⇧⌘X",
                                     enabled: canEndTool(item)) { if canEndTool(item) { manager.stop(item.id) } })
            result.append(ToolAction(id: "edit", title: tr("Edit Tool", "编辑工具"), symbol: "slider.horizontal.3", shortcut: "⌘E", enabled: !busy) { editTool(item.id) })
            result.append(ToolAction(id: "pin", title: item.isPinned ? tr("Unpin Tool", "取消置顶") : tr("Pin Tool", "置顶工具"),
                                     symbol: item.isPinned ? "pin.slash" : "pin", shortcut: "⌘P",
                                     enabled: saved != nil && !manager.isQuitting) { togglePin(item) })
            result.append(ToolAction(id: "logs", title: tr("View Logs", "查看日志"), symbol: "text.alignleft", shortcut: "⌘L", enabled: saved != nil) { showLogs(item.id) })
            if !item.openURL.isEmpty {
                result.append(ToolAction(id: "website", title: tr("Open Website", "打开网页"), symbol: "globe") { openWebpage(item.openURL) })
            }
            if item.start.kind == .script && !item.start.isEmpty {
                result.append(ToolAction(id: "reveal", title: tr("Reveal Start Script", "在访达中显示启动脚本"), symbol: "folder") {
                    revealScript(item.start.value, workingDirectory: item.workingDirectory)
                })
            }
            if busy {
                result.append(ToolAction(id: "force", title: tr("Force Stop…", "强制停止…"), symbol: "exclamationmark.octagon", destructive: true) { forceCandidate = item })
            }
            result.append(ToolAction(id: "delete", title: tr("Delete Configuration…", "删除配置…"), symbol: "trash", enabled: !busy, destructive: true) { deleteCandidate = item })
        }
        result.append(ToolAction(id: "new", title: tr("New Tool", "新建工具"), symbol: "plus", shortcut: "⌘N") { newTool() })
        result.append(ToolAction(id: "import", title: tr("Import Tools…", "导入工具…"), symbol: "square.and.arrow.down") { showImport() })
        result.append(ToolAction(id: "export", title: tr("Export Configuration…", "导出配置…"), symbol: "square.and.arrow.up", enabled: !manager.tools.isEmpty) { exportTools() })
        result.append(ToolAction(id: "configuration", title: tr("Open Configuration Folder", "打开配置文件夹"), symbol: "folder.badge.gearshape") { NSWorkspace.shared.open(manager.dataDirectory) })
        return result
    }

    private func toolIcon(_ item: ToolDefinition, size: CGFloat) -> some View {
        let accent: Color = item.start.kind == .shell ? .purple : .cyan
        return Image(systemName: item.openURL.isEmpty ? "terminal" : "square.stack.3d.up")
            .font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(accent.opacity(0.9))
            .frame(width: size, height: size).background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
    }
    private var separator: some View { Rectangle().fill(PaletteStyle.border).frame(height: 1) }
    private var footerDivider: some View { Rectangle().fill(PaletteStyle.border).frame(width: 1, height: 15) }
    private func sectionLabel(_ value: String) -> some View {
        Text(value).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(PaletteStyle.muted)
    }
    private func shortcut(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(PaletteStyle.muted).padding(.horizontal, 4).padding(.vertical, 3)
            .background(Color.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 4))
    }
    private func formField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 118, alignment: .leading)
            content()
        }
    }
    private func paletteTextField(_ placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain)
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .padding(10).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(PaletteStyle.border))
    }

    private func tool(_ id: UUID) -> ToolDefinition? { drafts[id] ?? savedTool(id) }
    private func savedTool(_ id: UUID) -> ToolDefinition? { manager.tools.first { $0.id == id } }
    private func isSaved(_ id: UUID) -> Bool { savedTool(id) != nil }
    private func isDirty(_ item: ToolDefinition) -> Bool { savedTool(item.id) != item }
    private func isBusy(_ id: UUID) -> Bool {
        let state = manager.state(for: id)
        return state.pid != nil || state.phase == .stopping
    }
    private func canStartTool(_ item: ToolDefinition) -> Bool {
        isSaved(item.id) && !isDirty(item) && !manager.sessionToolIDs.contains(item.id)
            && !isBusy(item.id) && !manager.isQuitting && !item.start.isEmpty
    }
    private func canEndTool(_ item: ToolDefinition) -> Bool {
        isSaved(item.id) && manager.sessionToolIDs.contains(item.id)
            && manager.state(for: item.id).phase != .stopping && !manager.isQuitting
    }
    private func syncDraftPins() {
        for saved in manager.tools {
            if var draft = drafts[saved.id], draft.isPinned != saved.isPinned {
                draft.isPinned = saved.isPinned
                drafts[saved.id] = draft
            }
        }
    }
    private func togglePin(_ item: ToolDefinition) {
        guard let saved = savedTool(item.id), !manager.isQuitting else { return }
        do {
            try manager.setPinned(item.id, !saved.isPinned)
            syncDraftPins()
        } catch { manager.errorMessage = error.localizedDescription }
    }
    private func binding(for id: UUID) -> Binding<ToolDefinition> {
        Binding(get: { tool(id) ?? ToolDefinition(id: id) }, set: { drafts[id] = $0 })
    }
    private func shortPath(_ path: String) -> String { NSString(string: path).abbreviatingWithTildeInPath }
    private func commandSummary(_ command: ToolCommand) -> String {
        if command.isEmpty { return tr("Not configured", "未配置") }
        if command.kind == .script { return URL(fileURLWithPath: command.value).lastPathComponent }
        return command.value.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? command.value
    }
    private func subtitle(_ item: ToolDefinition) -> String {
        if isDirty(item) { return tr("Continue setting up this tool", "继续设置此工具") }
        if !item.workingDirectory.isEmpty { return shortPath(item.workingDirectory) }
        return commandSummary(item.start)
    }
    private func phaseColor(_ phase: ToolPhase) -> Color {
        switch phase {
        case .idle: return Color.white.opacity(0.3)
        case .running: return .green
        case .stopping: return .orange
        case .external: return .cyan
        case .failed: return .red
        }
    }
    private func primaryAction(_ item: ToolDefinition) -> PrimaryToolAction {
        if isDirty(item) { return .edit }
        let phase = manager.state(for: item.id).phase
        if isBusy(item.id) || manager.sessionToolIDs.contains(item.id) || phase == .external {
            return item.openURL.isEmpty ? .logs : .website
        }
        return .start
    }
    private func primaryTitle(_ item: ToolDefinition) -> String {
        switch primaryAction(item) {
        case .edit: return tr("Continue Editing", "继续编辑")
        case .logs: return tr("View Logs", "查看日志")
        case .website: return tr("Open Website", "打开网页")
        case .start: return tr("Start Tool", "启动工具")
        }
    }
    private func primarySymbol(_ item: ToolDefinition) -> String {
        switch primaryAction(item) {
        case .edit: return "slider.horizontal.3"
        case .logs: return "text.alignleft"
        case .website: return "globe"
        case .start: return "play"
        }
    }
    private var primaryDisabled: Bool {
        guard let item = selectedTool else { return true }
        return primaryIsDisabled(item)
    }
    private func primaryIsDisabled(_ item: ToolDefinition) -> Bool {
        primaryAction(item) == .start && !canStartTool(item)
    }
    private func performPrimary() {
        guard let item = selectedTool else { return }
        performPrimary(item)
    }
    private func performPrimary(_ item: ToolDefinition) {
        guard !primaryIsDisabled(item) else { return }
        actionsOpen = false
        switch primaryAction(item) {
        case .edit: editTool(item.id)
        case .logs: showLogs(item.id)
        case .website: openWebpage(item.openURL)
        case .start: manager.start(item.id)
        }
    }
    private func ensureSelection() {
        if !filteredTools.contains(where: { $0.id == selectedID }) { selectedID = filteredTools.first?.id }
    }
    private func focusSearch() {
        guard page == .palette else { return }
        DispatchQueue.main.async { focusedField = .search }
    }
    private func newTool() {
        let item = ToolDefinition()
        drafts[item.id] = item
        selectedID = item.id
        page = .editor(item.id)
        actionsOpen = false
        DispatchQueue.main.async { focusedField = .name }
    }
    private func editTool(_ id: UUID) {
        guard !isBusy(id) else { return }
        selectedID = id
        page = .editor(id)
        actionsOpen = false
        DispatchQueue.main.async { focusedField = .name }
    }
    private func backToPalette() { page = .palette; actionsOpen = false; ensureSelection(); focusSearch() }
    private func saveAndReturn(_ item: ToolDefinition) {
        do {
            try manager.save(item)
            drafts[item.id] = nil
            query = ""
            selectedID = item.id
            backToPalette()
        } catch { manager.errorMessage = error.localizedDescription }
    }
    private func showLogs(_ id: UUID) { page = .logs(id); actionsOpen = false; focusedField = nil; refreshLog() }
    private func refreshLog() {
        guard case .logs(let id) = page else { return }
        let updated = manager.logText(for: id)
        if updated != logText { logText = updated }
    }
    private func toggleActions() {
        guard page == .palette else { return }
        actionsOpen.toggle()
        if actionsOpen { actionIndex = currentActions.firstIndex(where: \.enabled) ?? 0 }
        else { focusSearch() }
    }
    private func moveSelection(_ direction: Int) {
        let items = filteredTools
        guard !items.isEmpty else { return }
        let old = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = items[max(0, min(items.count - 1, old + direction))].id
    }
    private func moveAction(_ direction: Int) {
        let items = currentActions
        var next = actionIndex + direction
        while items.indices.contains(next) {
            if items[next].enabled { actionIndex = next; return }
            next += direction
        }
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let character = (event.charactersIgnoringModifiers ?? "").lowercased()
        if modifiers.contains(.command) && !modifiers.contains(.option) && !modifiers.contains(.control) {
            if modifiers.contains(.shift) && character == "x" {
                guard page == .palette else { return false }
                if let item = selectedTool, let stop = actions(for: item).first(where: { $0.id == "stop" }), stop.enabled { stop.perform() }
                return true
            }
            guard !modifiers.contains(.shift) else { return false }
            switch character {
            case "n": newTool(); return true
            case "k": if page == .palette { toggleActions(); return true }; return false
            case "f": if page == .palette { actionsOpen = false; focusSearch(); return true }; return false
            case "e": if page == .palette, let id = selectedID { editTool(id); return true }; return false
            case "p": if page == .palette, let item = selectedTool { togglePin(item); return true }; return false
            case "l": if page == .palette, let id = selectedID, isSaved(id) { showLogs(id); return true }; return false
            default: break
            }
            if event.keyCode == 36 || event.keyCode == 76, case .editor(let id) = page, let item = tool(id), !isBusy(id), !manager.isQuitting {
                saveAndReturn(item); return true
            }
            return false
        }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 53 {
            if actionsOpen { actionsOpen = false; focusSearch() }
            else if page != .palette { backToPalette() }
            else if !query.isEmpty { query = "" }
            else { collapseToMenuBar() }
            return true
        }
        guard page == .palette else { return false }
        if event.keyCode == 125 || event.keyCode == 126 {
            let direction = event.keyCode == 125 ? 1 : -1
            if actionsOpen { moveAction(direction) } else { moveSelection(direction) }
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if actionsOpen {
                let items = currentActions
                if items.indices.contains(actionIndex), items[actionIndex].enabled {
                    actionsOpen = false
                    items[actionIndex].perform()
                }
            } else { performPrimary() }
            return true
        }
        return false
    }

    private func deleteTool() {
        guard let item = deleteCandidate else { return }
        do {
            if isSaved(item.id) { try manager.delete(item.id) }
            drafts[item.id] = nil
            deleteCandidate = nil
            ensureSelection()
        } catch { deleteCandidate = nil; manager.errorMessage = error.localizedDescription }
    }
    private func chooseDirectory(for item: Binding<ToolDefinition>) {
        let panel = NSOpenPanel()
        panel.title = tr("Choose Working Directory", "选择工作目录")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !item.wrappedValue.workingDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NSString(string: item.wrappedValue.workingDirectory).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url { item.wrappedValue.workingDirectory = url.path }
    }
    private func openWebpage(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            manager.errorMessage = tr("Enter a complete website URL, such as http://localhost:8808.", "请输入完整的网页地址，例如 http://localhost:8808。")
            return
        }
        NSWorkspace.shared.open(url)
    }
    private func revealScript(_ value: String, workingDirectory: String) {
        NSWorkspace.shared.activateFileViewerSelecting([launcherScriptURL(value, workingDirectory: workingDirectory)])
    }
    private func revealLog(_ id: UUID) {
        let url = manager.logURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { manager.errorMessage = tr("This tool does not have a log file yet.", "此工具尚未生成日志文件。") }
    }
    private func importTools() {
        let panel = NSOpenPanel()
        panel.title = tr("Import Tool Configuration", "导入工具配置")
        panel.allowedContentTypes = [.json, UTType(filenameExtension: ToolImportSupport.fileExtension) ?? .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try manager.importTools(from: url)
                query = ""
                backToPalette()
            }
            catch { manager.errorMessage = error.localizedDescription }
        }
    }
    private func exportTools() {
        let panel = NSSavePanel()
        panel.title = tr("Export Tool Configuration", "导出工具配置")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MungTools.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try manager.export(to: url) }
            catch { manager.errorMessage = error.localizedDescription }
        }
    }
}

private struct LauncherCommandField: View {
    @ObservedObject private var preferences = AppPreferences.shared
    let title: String
    let subtitle: String
    @Binding var command: ToolCommand
    @Binding var workingDirectory: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.8))
                .frame(width: 118, alignment: .leading).padding(.top, 8)
            VStack(alignment: .leading, spacing: 9) {
                Picker(tr("Command type", "命令类型"), selection: $command.kind) {
                    Text(tr("Script File", "脚本文件")).tag(CommandKind.script)
                    Text(tr("Shell Command", "Shell 命令")).tag(CommandKind.shell)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                if command.kind == .script { scriptField }
                else { shellField }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(PaletteStyle.muted)
            }
        }
    }
    private var scriptField: some View {
        HStack(spacing: 8) {
            TextField(tr("Choose a .command, .sh, or executable script", "选择 .command、.sh 或可执行脚本"), text: $command.value)
                .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                .padding(10).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(PaletteStyle.border))
            Button(tr("Browse…", "浏览…"), action: chooseScript).buttonStyle(.bordered)
            if !command.isEmpty {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([launcherScriptURL(command.value, workingDirectory: workingDirectory)])
                } label: { Image(systemName: "folder") }.buttonStyle(.bordered).help(tr("Reveal script in Finder", "在访达中显示脚本"))
            }
        }
    }
    private var shellField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $command.value)
                .font(.system(size: 11, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(7).frame(height: 76).background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(PaletteStyle.border))
            Text(tr("Runs with /bin/zsh. Multiple lines are supported.", "使用 /bin/zsh 执行，支持多行命令。")).font(.system(size: 10)).foregroundStyle(PaletteStyle.muted)
        }
    }
    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose Script File", "选择脚本文件")
        panel.message = tr("Select a .command, .sh, or another executable script. The original file will be used.", "选择 .command、.sh 或其他可执行脚本。将直接使用原始文件。")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !command.value.isEmpty {
            panel.directoryURL = launcherScriptURL(command.value, workingDirectory: workingDirectory).deletingLastPathComponent()
        } else if !workingDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NSString(string: workingDirectory).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            command.value = url.path
            if workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { workingDirectory = url.deletingLastPathComponent().path }
        }
    }
}

private struct LauncherKeyboardHandler: NSViewRepresentable {
    let handle: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.handle = handle }
    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    final class Coordinator {
        weak var view: NSView?
        var handle: (NSEvent) -> Bool
        private var monitor: Any?
        init(handle: @escaping (NSEvent) -> Bool) { self.handle = handle }
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.view?.window,
                      event.window === window, NSApp.keyWindow === window,
                      NSApp.modalWindow == nil, window.attachedSheet == nil else { return event }
                return self.handle(event) ? nil : event
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

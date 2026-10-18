import Foundation

enum ToolImportSupport {
    static let fileExtension = "mungtools"
    static let typeIdentifier = "pro.mungb.tool-launcher.import"
    static let guideURL = "https://github.com/MungbPro/MungTools/blob/main/docs/CODEX-IMPORT.md"

    static func validateDocumentURL(_ url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == fileExtension else {
            throw LauncherError(tr("Choose a .mungtools import file.", "请选择 .mungtools 导入文件。"))
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw LauncherError(tr("The import must be a regular file.", "导入内容必须是普通文件。"))
        }
        guard let size = values.fileSize, size <= 4 * 1_024 * 1_024 else {
            throw LauncherError(tr("The import file is too large. Use a file smaller than 4 MB.", "导入文件过大，请使用小于 4 MB 的文件。"))
        }
    }

    static func codexPrompt(language: AppLanguage) -> String {
        if language == .simplifiedChinese {
            return """
            请把我的本地工具导入 Mung Tools（熊梦白 AI 工具箱）。先阅读导入说明：\(guideURL)。在我授权的项目文件夹中查找并阅读 .command 文件，配对各工具的 Start 和 Stop；不要执行脚本，遇到不明确的配对先问我。使用现有脚本，不要修改它们，也不要直接编辑工具箱正在使用的 tools.json。生成 version 1 的 UTF-8 JSON 文件 import.mungtools，使用稳定的 UUID 和绝对路径，保留已有工具。完成后用 `open -a "Mung Tools" "/绝对路径/import.mungtools"` 交给工具箱导入，或告诉我在 Import 中选择该文件。导入不会启动工具。使用工具箱的本地文件导入，不要接入任何 API。
            """
        }
        return """
        Import my local tools into Mung Tools. Read the import guide first: \(guideURL). Find and read .command files in the project folders I authorize, pairing each tool's Start and Stop scripts. Do not run scripts; ask me about ambiguous matches. Use the existing scripts without changing them, and do not edit Mung Tools' live tools.json. Create import.mungtools as version 1 UTF-8 JSON with stable UUIDs and absolute paths, preserving existing tools. Then hand it to the app with `open -a "Mung Tools" "/absolute/path/import.mungtools"`, or tell me to select it in Import. Importing must not start tools. Use Mung Tools' local file import; do not add any API integration.
        """
    }
}

extension Notification.Name {
    static let mungToolsImported = Notification.Name("MungToolsImported")
}

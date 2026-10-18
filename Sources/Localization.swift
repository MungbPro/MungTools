import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    var displayName: String { self == .english ? "English" : "简体中文" }
    var appName: String { self == .english ? "Mung Tools" : "熊梦白 AI 工具箱" }
    var creatorLinkTitle: String { self == .english ? "More About Mung" : "关注我-熊梦白" }

    static var current: AppLanguage {
        saved(in: LanguageStorage.defaults)
    }

    static func saved(in defaults: UserDefaults) -> AppLanguage {
        defaults.string(forKey: LanguageStorage.key).flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

private enum LanguageStorage {
    static let key = "MungTools.interfaceLanguage"
    static let defaults: UserDefaults = {
        // An isolated launcher instance must not change the installed app's
        // preferences while its interface is being tested.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
            let path = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL.path
            let digest = path.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
            return UserDefaults(suiteName: "pro.mungb.tool-launcher.isolated.\(String(digest, radix: 16))") ?? .standard
        }
        return .standard
    }()
}

extension Notification.Name {
    static let mungToolsLanguageDidChange = Notification.Name("MungToolsLanguageDidChange")
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private let defaults: UserDefaults
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: LanguageStorage.key)
            NotificationCenter.default.post(name: .mungToolsLanguageDidChange, object: self)
        }
    }

    init(defaults: UserDefaults? = nil) {
        let storage = defaults ?? LanguageStorage.defaults
        self.defaults = storage
        self.language = AppLanguage.saved(in: storage)
    }
}

func tr(_ english: String, _ simplifiedChinese: String) -> String {
    AppLanguage.current == .simplifiedChinese ? simplifiedChinese : english
}

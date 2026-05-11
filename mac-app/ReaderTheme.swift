import Foundation

enum ReaderTheme: String, CaseIterable {
    private static let defaultsKey = "readerTheme"

    case original
    case dark

    var title: String {
        switch self {
        case .original:
            return AppText.localized("浅色模式", "Light Mode")
        case .dark:
            return AppText.localized("深色模式", "Dark Mode")
        }
    }

    var helpText: String {
        AppText.localized("选择 PDF、EPUB 和 DOCX 阅读区域的显示模式。", "Choose the display mode for PDF, EPUB, and DOCX reading views.")
    }

    static var selected: ReaderTheme {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
                  let theme = ReaderTheme(rawValue: rawValue) else {
                return .original
            }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            UserDefaults.standard.synchronize()
        }
    }
}

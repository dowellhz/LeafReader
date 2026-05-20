import Foundation

enum ReaderTheme: String, CaseIterable {
    private static let defaultsKey = "readerTheme"
    private static let pdfDimmingKey = "pdfDimmingStrength"

    case original
    case eyeCare
    case dark

    var title: String {
        switch self {
        case .original:
            return AppText.localized("浅色模式", "Light Mode")
        case .eyeCare:
            return AppText.localized("护眼模式", "Eye Care Mode")
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

    static var pdfDimmingStrength: Double {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: pdfDimmingKey) != nil else { return 0.34 }
            return min(max(defaults.double(forKey: pdfDimmingKey), 0), 0.6)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0), 0.6), forKey: pdfDimmingKey)
            UserDefaults.standard.synchronize()
        }
    }
}

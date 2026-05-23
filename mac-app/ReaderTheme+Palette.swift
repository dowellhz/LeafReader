import Cocoa

extension ReaderTheme {
    var primaryTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
        case .dark:
            return NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
        }
    }

    var secondaryTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.36, green: 0.39, blue: 0.48, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.45, green: 0.39, blue: 0.26, alpha: 1)
        case .dark:
            return NSColor(red: 0.62, green: 0.67, blue: 0.74, alpha: 1)
        }
    }

    var mutedTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.52, green: 0.55, blue: 0.62, alpha: 1)
        case .eyeCare:
            return accentColor
        case .dark:
            return NSColor(red: 0.54, green: 0.58, blue: 0.64, alpha: 1)
        }
    }

    var accentColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.55, green: 0.38, blue: 0.14, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.55, blue: 1.00, alpha: 1)
        }
    }

    var strongAccentColor: NSColor {
        switch self {
        case .original, .dark:
            return accentColor
        case .eyeCare:
            return NSColor(red: 0.42, green: 0.29, blue: 0.08, alpha: 1)
        }
    }

    var primaryActionTextColor: NSColor {
        switch self {
        case .original, .dark:
            return .white
        case .eyeCare:
            return NSColor(red: 0.97, green: 0.93, blue: 0.78, alpha: 1)
        }
    }

    func searchUnderlineColor(isHighlighted: Bool) -> NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.72, green: 0.76, blue: 0.82, alpha: isHighlighted ? 1 : 0.9)
        case .eyeCare:
            return accentColor.withAlphaComponent(isHighlighted ? 1 : 0.9)
        case .dark:
            return NSColor(red: 0.42, green: 0.48, blue: 0.56, alpha: isHighlighted ? 1 : 0.8)
        }
    }

    func sideHandleFillColor(isHighlighted: Bool) -> NSColor {
        switch self {
        case .original:
            return NSColor(red: isHighlighted ? 0.16 : 0.22, green: isHighlighted ? 0.42 : 0.50, blue: isHighlighted ? 0.90 : 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: isHighlighted ? 0.45 : 0.55, green: isHighlighted ? 0.31 : 0.38, blue: isHighlighted ? 0.10 : 0.14, alpha: 1)
        case .dark:
            return NSColor(red: isHighlighted ? 0.24 : 0.32, green: isHighlighted ? 0.45 : 0.55, blue: isHighlighted ? 0.88 : 1.00, alpha: 1)
        }
    }
}

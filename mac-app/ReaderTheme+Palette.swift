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

    var aiSourceUnderlineColor: NSColor {
        switch self {
        case .original:
            return accentColor.withAlphaComponent(0.72)
        case .eyeCare:
            return strongAccentColor.withAlphaComponent(0.78)
        case .dark:
            return NSColor(red: 0.58, green: 0.72, blue: 1.0, alpha: 0.82)
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

    var chromeBackgroundColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.935, green: 0.945, blue: 0.96, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.90, green: 0.87, blue: 0.76, alpha: 1)
        case .dark:
            return NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        }
    }

    var toolbarBackgroundColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.972, green: 0.978, blue: 0.986, alpha: 0.98)
        case .eyeCare:
            return NSColor(red: 0.86, green: 0.82, blue: 0.68, alpha: 0.97)
        case .dark:
            return NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
        }
    }

    var toolbarBorderColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.71, green: 0.66, blue: 0.50, alpha: 1)
        case .dark:
            return NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
        }
    }

    var controlBackgroundColor: NSColor {
        switch self {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.73, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    var controlBorderColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.67, green: 0.61, blue: 0.45, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    var resizeHandleColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.72, green: 0.67, blue: 0.50, alpha: 1)
        case .dark:
            return NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
        }
    }

    var searchOverlayBackgroundColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.995, green: 0.985, blue: 0.995, alpha: 0.98)
        case .eyeCare:
            return NSColor(red: 0.90, green: 0.85, blue: 0.70, alpha: 0.98)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 0.98)
        }
    }

    var searchOverlayBorderColor: NSColor {
        switch self {
        case .original:
            return .clear
        case .eyeCare:
            return NSColor(red: 0.67, green: 0.60, blue: 0.42, alpha: 1)
        case .dark:
            return NSColor(red: 0.24, green: 0.28, blue: 0.34, alpha: 1)
        }
    }

    var searchOverlaySeparatorColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.82, green: 0.72, blue: 0.98, alpha: 0.65)
        case .eyeCare:
            return strongAccentColor.withAlphaComponent(0.52)
        case .dark:
            return secondaryTextColor.withAlphaComponent(0.42)
        }
    }

    var vocabularyPanelBackgroundColor: NSColor {
        switch self {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    var vocabularyPrimaryTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1)
        }
    }

    var vocabularySecondaryTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        case .eyeCare:
            return secondaryTextColor
        case .dark:
            return NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1)
        }
    }

    var vocabularyBorderColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    var vocabularyCardBackgroundColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.88, green: 0.83, blue: 0.68, alpha: 1)
        case .dark:
            return NSColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1)
        }
    }

    var vocabularyCardBorderColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    var vocabularyBodyTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.22, green: 0.25, blue: 0.31, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.25, green: 0.20, blue: 0.12, alpha: 1)
        case .dark:
            return NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1)
        }
    }

    var vocabularyButtonBackgroundColor: NSColor {
        switch self {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.92, green: 0.87, blue: 0.72, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    var vocabularyAccentColor: NSColor {
        strongAccentColor
    }

    var vocabularySelectionBackgroundColor: NSColor {
        vocabularyAccentColor.withAlphaComponent(self == .eyeCare ? 0.24 : 0.20)
    }

    var shelfBackgroundColor: NSColor {
        vocabularyPanelBackgroundColor
    }

    var shelfPrimaryTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        }
    }

    var shelfSecondaryTextColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.45, green: 0.49, blue: 0.60, alpha: 1)
        case .eyeCare:
            return secondaryTextColor
        case .dark:
            return NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
    }

    var shelfBorderColor: NSColor {
        switch self {
        case .original:
            return NSColor(red: 0.84, green: 0.87, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.28, green: 0.34, blue: 0.42, alpha: 1)
        }
    }

    var shelfButtonBackgroundColor: NSColor {
        switch self {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.89, green: 0.84, blue: 0.69, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
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

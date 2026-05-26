import Cocoa

enum ReadingNoteTheme {
    static func panelBackground(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.87, green: 0.81, blue: 0.61, alpha: 1)
        case .dark:
            return NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        }
    }

    static func panelBorder(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.84, green: 0.86, blue: 0.90, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.62, green: 0.54, blue: 0.34, alpha: 1)
        case .dark:
            return NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
        }
    }

    static func cardBackground(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor.white.withAlphaComponent(0.96)
        case .eyeCare:
            return NSColor(red: 0.95, green: 0.90, blue: 0.76, alpha: 0.92)
        case .dark:
            return NSColor(red: 0.14, green: 0.17, blue: 0.22, alpha: 1)
        }
    }

    static func insetBackground(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.86, green: 0.78, blue: 0.55, alpha: 1)
        case .dark:
            return NSColor(red: 0.19, green: 0.23, blue: 0.29, alpha: 1)
        }
    }

    static func editorBackground(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor.white
        case .eyeCare:
            return NSColor(red: 0.97, green: 0.93, blue: 0.84, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        }
    }

    static func primaryText(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .dark:
            return NSColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.12, green: 0.10, blue: 0.07, alpha: 1)
        case .original:
            return NSColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        }
    }

    static func secondaryText(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .dark:
            return NSColor(red: 0.68, green: 0.72, blue: 0.78, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.42, green: 0.36, blue: 0.24, alpha: 1)
        case .original:
            return NSColor(red: 0.39, green: 0.43, blue: 0.50, alpha: 1)
        }
    }

    static func accent(_ theme: ReaderTheme) -> NSColor {
        theme.strongAccentColor
    }

    static func secondaryButtonBackground(_ theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor.white.withAlphaComponent(0.92)
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.84, blue: 0.65, alpha: 0.76)
        case .dark:
            return NSColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1)
        }
    }
}

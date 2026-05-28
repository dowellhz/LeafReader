import Cocoa

struct DiagnosticsPanelTheme {
    let isDark: Bool
    let backgroundColor: NSColor
    let borderColor: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let okColor: NSColor
    let rowFill: NSColor
    let primaryButtonBackground: NSColor
    let secondaryButtonBackground: NSColor
    let primaryButtonText: NSColor
    let secondaryButtonText: NSColor

    static func make(from theme: ReaderTheme) -> DiagnosticsPanelTheme {
        switch theme {
        case .original:
            return DiagnosticsPanelTheme(
                isDark: false,
                backgroundColor: NSColor(red: 0.985, green: 0.99, blue: 0.992, alpha: 1),
                borderColor: NSColor(red: 0.84, green: 0.87, blue: 0.90, alpha: 1),
                primaryText: NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1),
                secondaryText: NSColor(red: 0.38, green: 0.42, blue: 0.46, alpha: 1),
                okColor: NSColor(red: 0.03, green: 0.45, blue: 0.90, alpha: 1),
                rowFill: NSColor.white.withAlphaComponent(0.96),
                primaryButtonBackground: NSColor(red: 0.03, green: 0.45, blue: 0.90, alpha: 1),
                secondaryButtonBackground: NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1),
                primaryButtonText: .white,
                secondaryButtonText: NSColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
            )
        case .eyeCare:
            return DiagnosticsPanelTheme(
                isDark: false,
                backgroundColor: NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1),
                borderColor: NSColor(red: 0.65, green: 0.56, blue: 0.36, alpha: 0.7),
                primaryText: NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1),
                secondaryText: theme.secondaryTextColor,
                okColor: NSColor(red: 0.36, green: 0.31, blue: 0.21, alpha: 1),
                rowFill: NSColor(red: 0.89, green: 0.84, blue: 0.69, alpha: 1),
                primaryButtonBackground: NSColor(red: 0.46, green: 0.30, blue: 0.08, alpha: 1),
                secondaryButtonBackground: NSColor.white.withAlphaComponent(0.12),
                primaryButtonText: .white,
                secondaryButtonText: NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
            )
        case .dark:
            return DiagnosticsPanelTheme(
                isDark: true,
                backgroundColor: NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1),
                borderColor: NSColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 1),
                primaryText: NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1),
                secondaryText: NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1),
                okColor: NSColor(red: 0.34, green: 0.56, blue: 0.95, alpha: 1),
                rowFill: NSColor.white.withAlphaComponent(0.04),
                primaryButtonBackground: NSColor(red: 0.34, green: 0.56, blue: 0.95, alpha: 1),
                secondaryButtonBackground: NSColor.white.withAlphaComponent(0.04),
                primaryButtonText: .white,
                secondaryButtonText: NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            )
        }
    }
}

import Cocoa

extension NSAlert {
    func applyLeafStyle(theme: ReaderTheme = ReaderTheme.selected) {
        window.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        window.backgroundColor = backgroundColor(for: theme)
        window.isOpaque = true
        applyLeafStyle(to: window.contentView, theme: theme)
        if let accessoryView {
            applyLeafStyle(to: accessoryView, theme: theme)
        }
    }

    private func applyLeafStyle(to view: NSView?, theme: ReaderTheme) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = backgroundColor(for: theme).cgColor
        if let label = view as? NSTextField {
            label.textColor = label.font?.pointSize ?? 13 >= 14 ? primaryTextColor(for: theme) : secondaryTextColor(for: theme)
        } else if let button = view as? NSButton, !button.title.isEmpty {
            styleButton(button, theme: theme)
        } else if let imageView = view as? NSImageView {
            imageView.contentTintColor = accentColor(for: theme)
        }
        for subview in view.subviews {
            applyLeafStyle(to: subview, theme: theme)
        }
    }

    private func styleButton(_ button: NSButton, theme: ReaderTheme) {
        let title = button.title.isEmpty ? button.attributedTitle.string : button.title
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = accentColor(for: theme).cgColor
        button.layer?.borderColor = accentColor(for: theme).cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = true
        button.contentTintColor = buttonTextColor(for: theme)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: button.font ?? AppFont.semibold(ofSize: 13),
                .foregroundColor: buttonTextColor(for: theme)
            ]
        )
    }

    private func backgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    private func primaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        }
    }

    private func secondaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.38, green: 0.41, blue: 0.49, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.45, green: 0.39, blue: 0.27, alpha: 1)
        case .dark:
            return NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
    }

    private func accentColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.55, green: 0.38, blue: 0.14, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
        }
    }

    private func buttonTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original, .dark:
            return .white
        case .eyeCare:
            return NSColor(red: 0.97, green: 0.93, blue: 0.78, alpha: 1)
        }
    }
}

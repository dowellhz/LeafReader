import Cocoa

extension AISettingsPanelController {
    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = weight == .regular
            ? NSFont.systemFont(ofSize: size, weight: .regular)
            : AppFont.semibold(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func settingsTitleIcon(primaryText: NSColor) -> NSView {
        let metrics = AISettingsLayoutMetrics()
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = false
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: metrics.titleIconSymbolSize, weight: .regular))
        imageView.identifier = Identifiers.settingsTitleIcon
        imageView.contentTintColor = settingsTitleIconColor(for: ReaderTheme.selected, fallback: primaryText)
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: metrics.titleIconSymbolSize),
            imageView.heightAnchor.constraint(equalToConstant: metrics.titleIconSymbolSize)
        ])
        return container
    }

    func themedPage(backgroundColor: NSColor) -> NSView {
        let view = NSView()
        view.identifier = Identifiers.settingsFormSurface
        view.wantsLayer = true
        view.layer?.backgroundColor = backgroundColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func inputField(_ text: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSTextField {
        let field = SettingsTextField(string: text)
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.font = AppFont.semibold(ofSize: fontSize)
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.textColor = textColor
        applyThemedFieldChrome(to: field, backgroundColor: backgroundColor)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    func configureKeyField(_ field: NSTextField, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) {
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.font = AppFont.semibold(ofSize: fontSize)
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.focusRingType = .none
        field.textColor = textColor
        applyThemedFieldChrome(to: field, backgroundColor: backgroundColor)
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    func popup(items: [(String, String)], selected: String, fontSize: CGFloat) -> NSPopUpButton {
        let popup = ThemedSettingsPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = AppFont.semibold(ofSize: fontSize)
        popup.isBordered = false
        popup.translatesAutoresizingMaskIntoConstraints = false
        for item in items {
            popup.addItem(withTitle: item.0)
            popup.lastItem?.representedObject = item.1
            popup.lastItem?.isEnabled = true
        }
        popup.isEnabled = true
        popup.menu?.autoenablesItems = false
        if let index = items.firstIndex(where: { $0.1 == selected }) {
            popup.selectItem(at: index)
        }
        stylePopupForCurrentTheme(popup)
        return popup
    }

    func settingsCheckbox(title: String = "", isOn: Bool, theme: ReaderTheme, fontSize: CGFloat) -> ThemedSettingsCheckbox {
        let checkbox = title.isEmpty ? ThemedSettingsCheckbox() : ThemedSettingsCheckbox(title: title)
        checkbox.theme = theme
        checkbox.font = AppFont.semibold(ofSize: fontSize)
        checkbox.lineBreakMode = .byTruncatingTail
        checkbox.state = isOn ? .on : .off
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        return checkbox
    }

    func stylePopupForCurrentTheme(_ popup: NSPopUpButton) {
        let theme = ReaderTheme.selected
        (popup as? ThemedSettingsPopUpButton)?.theme = theme
        popup.wantsLayer = true
        popup.layer?.backgroundColor = fieldBackground().cgColor
        popup.layer?.borderWidth = 1
        popup.layer?.borderColor = settingsBorderColor(for: theme).cgColor
        popup.layer?.cornerRadius = 8
        popup.contentTintColor = settingsPrimaryTextColor(for: theme)
    }

    func applyThemedFieldChrome(to field: NSTextField, backgroundColor: NSColor) {
        field.wantsLayer = true
        field.layer?.backgroundColor = backgroundColor.cgColor
        field.layer?.borderWidth = 1
        field.layer?.borderColor = settingsBorderColor(for: ReaderTheme.selected).cgColor
        field.layer?.cornerRadius = 8
        field.layer?.masksToBounds = true
    }

    func cacheActionButton(
        title: String,
        symbol: String,
        tint: NSColor,
        target: AnyObject,
        action: Selector
    ) -> NSButton {
        let theme = ReaderTheme.selected
        let button = ThemedSettingsActionButton(title: title, target: target, action: action)
        button.leadingSymbolName = symbol
        button.leadingSymbolBaseColor = tint
        button.leadingSymbolColor = settingsActionIconColor(tint, for: theme)
        styleSettingsActionButton(
            button,
            backgroundColor: settingsButtonBackgroundColor(for: theme),
            titleColor: settingsPrimaryTextColor(for: theme),
            borderColor: settingsBorderColor(for: theme)
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func settingsActionIconColor(_ tint: NSColor, for theme: ReaderTheme) -> NSColor {
        settingsPrimaryTextColor(for: theme)
    }

    func settingsActionButton(title: String, target: AnyObject, action: Selector, isPrimary: Bool = false) -> ThemedSettingsActionButton {
        let button = ThemedSettingsActionButton(title: title, target: target, action: action)
        if isPrimary {
            button.identifier = Identifiers.saveButton
        }
        let theme = ReaderTheme.selected
        styleSettingsActionButton(
            button,
            backgroundColor: isPrimary ? settingsPrimaryActionBackgroundColor(for: theme) : settingsButtonBackgroundColor(for: theme),
            titleColor: isPrimary ? settingsPrimaryActionTextColor(for: theme) : settingsPrimaryTextColor(for: theme),
            borderColor: isPrimary ? settingsPrimaryActionBorderColor(for: theme) : settingsBorderColor(for: theme)
        )
        button.controlSize = .large
        button.lineBreakMode = .byTruncatingTail
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func speechDownloadProgressIndicator() -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.controlSize = .small
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.doubleValue = 0
        indicator.isHidden = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }

    func settingsCard() -> NSView {
        let view = NSView()
        view.identifier = Identifiers.settingsCard
        view.wantsLayer = true
        let theme = ReaderTheme.selected
        view.layer?.backgroundColor = settingsCardBackgroundColor(for: theme).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = settingsBorderColor(for: theme).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func settingsSpeechRowCard() -> NSView {
        let view = settingsCard()
        view.identifier = Identifiers.settingsSpeechRowCard
        let theme = ReaderTheme.selected
        view.layer?.backgroundColor = settingsSpeechRowBackgroundColor(for: theme).cgColor
        view.layer?.cornerRadius = 9
        view.layer?.borderWidth = 1
        return view
    }

    func fieldBackground() -> NSColor {
        switch ReaderTheme.selected {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.87, green: 0.82, blue: 0.67, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    func settingsCardBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.86, green: 0.81, blue: 0.66, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    func settingsFormBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.995, green: 0.992, blue: 0.985, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.90, green: 0.86, blue: 0.71, alpha: 1)
        case .dark:
            return NSColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1)
        }
    }

    func settingsSpeechRowBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 0.92)
        case .eyeCare:
            return NSColor(red: 0.89, green: 0.84, blue: 0.68, alpha: 0.72)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 0.92)
        }
    }

    func settingsTitleIconColor(for theme: ReaderTheme, fallback: NSColor) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.42, green: 0.29, blue: 0.08, alpha: 1)
        case .dark:
            return fallback
        }
    }

    func settingsButtonBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.89, green: 0.84, blue: 0.69, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func settingsBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    func settingsPrimaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        }
    }

    func styleSettingsActionButton(
        _ button: NSButton,
        backgroundColor: NSColor,
        titleColor: NSColor,
        borderColor: NSColor
    ) {
        let displayTitle: String
        if button.identifier == Identifiers.saveButton {
            displayTitle = AppText.confirm
        } else if !button.title.isEmpty {
            displayTitle = button.title
        } else if !button.attributedTitle.string.isEmpty {
            displayTitle = button.attributedTitle.string
        } else {
            displayTitle = ""
        }
        if let themedButton = button as? ThemedSettingsActionButton {
            themedButton.title = displayTitle
            themedButton.fillColor = backgroundColor
            themedButton.labelColor = titleColor
            themedButton.strokeColor = borderColor
            themedButton.font = AppFont.semibold(ofSize: 14)
            return
        }
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = borderColor.cgColor
        button.layer?.masksToBounds = true
        button.font = AppFont.semibold(ofSize: 14)
        button.title = displayTitle
        button.attributedTitle = NSAttributedString(
            string: displayTitle,
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: titleColor
            ]
        )
        button.lineBreakMode = .byTruncatingTail
    }
}

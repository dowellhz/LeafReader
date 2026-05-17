import Cocoa

extension AISettingsPanelController {
    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = AppFont.semibold(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func inputField(_ text: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSTextField {
        let field = SettingsTextField(string: text)
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.font = AppFont.semibold(ofSize: fontSize)
        field.isBordered = true
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.textColor = textColor
        field.backgroundColor = backgroundColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    func comboField(items: [String], selected: String, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.addItems(withObjectValues: items)
        comboBox.stringValue = selected.isEmpty ? placeholder : selected
        comboBox.placeholderString = placeholder
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.numberOfVisibleItems = min(8, max(1, items.count))
        comboBox.controlSize = .regular
        comboBox.font = AppFont.semibold(ofSize: fontSize)
        comboBox.isBordered = true
        comboBox.drawsBackground = true
        comboBox.isEditable = true
        comboBox.isSelectable = true
        comboBox.textColor = textColor
        comboBox.backgroundColor = backgroundColor
        comboBox.translatesAutoresizingMaskIntoConstraints = false
        return comboBox
    }

    func configureKeyField(_ field: NSTextField, placeholder: String, fontSize: CGFloat, textColor: NSColor, backgroundColor: NSColor) {
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.font = AppFont.semibold(ofSize: fontSize)
        field.isBordered = true
        field.drawsBackground = true
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.textColor = textColor
        field.backgroundColor = backgroundColor
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    func popup(items: [(String, String)], selected: String, fontSize: CGFloat) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .large
        popup.font = AppFont.semibold(ofSize: fontSize)
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
        return popup
    }

    func cacheActionButton(
        title: String,
        symbol: String,
        tint: NSColor,
        target: AnyObject,
        action: Selector,
        isDark: Bool
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = (isDark ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1) : .white).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = (isDark
            ? NSColor(red: 0.24, green: 0.29, blue: 0.36, alpha: 1)
            : NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        ).cgColor
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = tint
        button.font = AppFont.semibold(ofSize: 14)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: isDark ? NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1) : NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
            ]
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func settingsCard(isDark: Bool) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
            : NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        ).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = (isDark
            ? NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            : NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        ).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func fieldBackground(isDark: Bool) -> NSColor {
        isDark ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1) : .white
    }

    func styleSettingsActionButton(
        _ button: NSButton,
        backgroundColor: NSColor,
        titleColor: NSColor,
        borderColor: NSColor
    ) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = borderColor.cgColor
        button.layer?.masksToBounds = true
        button.font = AppFont.semibold(ofSize: 14)
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .font: AppFont.semibold(ofSize: 14),
                .foregroundColor: titleColor
            ]
        )
        button.lineBreakMode = .byTruncatingTail
    }
}

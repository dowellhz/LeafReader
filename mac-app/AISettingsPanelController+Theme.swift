import Cocoa

extension AISettingsPanelController {
    static var pdfBrightnessSliderMaximum: Double { PDFBrightnessPolicy.sliderMaximum }

    @objc func themeChanged(_ sender: NSPopUpButton) {
        if let rawTheme = sender.selectedItem?.representedObject as? String,
           let theme = ReaderTheme(rawValue: rawTheme) {
            ReaderTheme.selected = theme
            applySettingsPanelTheme(theme)
            onAppearanceChanged?()
        }
        updatePDFDimmingControlsVisibility()
    }

    @objc func pdfDimmingSliderChanged(_ sender: ThemedSettingsSlider) {
        ReaderTheme.pdfDimmingStrength = pdfDimmingStrength(forBrightnessSliderValue: sender.doubleValue)
        onAppearanceChanged?()
    }

    func updatePDFDimmingControlsVisibility() {
        let rawTheme = themePopup?.selectedItem?.representedObject as? String ?? ReaderTheme.selected.rawValue
        let shouldShow = ReaderTheme(rawValue: rawTheme) != .original
        pdfDimmingLabel?.isHidden = !shouldShow
        pdfDimmingSlider?.isHidden = !shouldShow
        pdfDimmingLabelTopConstraint?.isActive = shouldShow
        speakSelectedWordTopToDimmingConstraint?.isActive = shouldShow
        speakSelectedWordTopToThemeConstraint?.isActive = !shouldShow
        if shouldShow {
            NSLayoutConstraint.deactivate(pdfDimmingCollapsedConstraints)
        } else {
            NSLayoutConstraint.activate(pdfDimmingCollapsedConstraints)
        }
    }

    func pdfBrightnessSliderValue(forDimmingStrength dimmingStrength: Double) -> Double {
        PDFBrightnessPolicy.sliderValue(forDimmingStrength: dimmingStrength)
    }

    func pdfDimmingStrength(forBrightnessSliderValue brightnessValue: Double) -> Double {
        PDFBrightnessPolicy.dimmingStrength(forSliderValue: brightnessValue)
    }

    func applySettingsPanelTheme(_ theme: ReaderTheme) {
        panel?.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel?.contentView?.layer?.backgroundColor = settingsPanelBackgroundColor(for: theme).cgColor
        panel?.contentView?.layer?.borderColor = settingsPanelBorderColor(for: theme).cgColor
        applySettingsTheme(to: panel?.contentView, theme: theme)
    }

    func applySettingsTheme(to view: NSView?, theme: ReaderTheme) {
        guard let view else { return }
        if let tabs = view as? SettingsTabsView {
            tabs.refreshTheme()
            return
        }
        applySettingsThemeIfNeeded(to: view, theme: theme)
        for subview in view.subviews {
            applySettingsTheme(to: subview, theme: theme)
        }
    }

    private func applySettingsThemeIfNeeded(to view: NSView, theme: ReaderTheme) {
        if let popup = view as? ThemedSettingsPopUpButton {
            popup.theme = theme
            stylePopupForCurrentTheme(popup)
        } else if let slider = view as? ThemedSettingsSlider {
            slider.theme = theme
        } else if let checkbox = view as? ThemedSettingsCheckbox {
            checkbox.theme = theme
        } else if let field = view as? NSTextField {
            applySettingsFieldTheme(field, theme: theme)
        } else if let button = view as? NSButton {
            applySettingsButtonTheme(button, theme: theme)
        }
        applySettingsContainerThemeIfNeeded(to: view, theme: theme)
    }

    private func applySettingsFieldTheme(_ field: NSTextField, theme: ReaderTheme) {
        field.textColor = settingsTextColor(for: field, theme: theme)
        if field.isEditable || field is NSSecureTextField || field is NSComboBox {
            field.layer?.backgroundColor = settingsFieldBackgroundColor(for: theme).cgColor
            field.layer?.borderColor = settingsBorderColor(for: theme).cgColor
        }
    }

    private func applySettingsContainerThemeIfNeeded(to view: NSView, theme: ReaderTheme) {
        if let scrollView = view as? NSScrollView {
            scrollView.contentView.drawsBackground = true
            scrollView.contentView.backgroundColor = settingsContainerBackgroundColor(for: theme)
            scrollView.documentView?.wantsLayer = true
            scrollView.documentView?.layer?.backgroundColor = settingsContainerBackgroundColor(for: theme).cgColor
        } else if shouldThemeSettingsContainer(view) {
            view.wantsLayer = true
            view.layer?.backgroundColor = settingsContainerBackgroundColor(for: theme).cgColor
            if (view.layer?.borderWidth ?? 0) > 0 {
                view.layer?.borderColor = settingsBorderColor(for: theme).cgColor
            }
        }
    }

    private func applySettingsButtonTheme(_ button: NSButton, theme: ReaderTheme) {
        if button.identifier == Identifiers.saveButton {
            styleSettingsActionButton(
                button,
                backgroundColor: settingsPrimaryActionBackgroundColor(for: theme),
                titleColor: settingsPrimaryActionTextColor(for: theme),
                borderColor: settingsPrimaryActionBorderColor(for: theme)
            )
        } else if button.title.isEmpty {
            button.contentTintColor = settingsPrimaryTextColor(for: theme)
        } else {
            styleSettingsActionButton(
                button,
                backgroundColor: settingsButtonBackgroundColor(for: theme),
                titleColor: settingsPrimaryTextColor(for: theme),
                borderColor: settingsBorderColor(for: theme)
            )
        }
    }

    private func settingsTextColor(for field: NSTextField, theme: ReaderTheme) -> NSColor {
        if field.isEditable || field is NSSecureTextField || field is NSComboBox {
            return settingsPrimaryTextColor(for: theme)
        }
        let size = field.font?.pointSize ?? 14
        return size <= 13 ? settingsSecondaryTextColor(for: theme) : settingsPrimaryTextColor(for: theme)
    }

    private func shouldThemeSettingsContainer(_ view: NSView) -> Bool {
        view !== panel?.contentView && (view.layer?.backgroundColor != nil || (view.layer?.borderWidth ?? 0) > 0)
    }

    private func settingsContainerBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme == .dark ? settingsCardBackgroundColor(for: theme) : settingsPanelBackgroundColor(for: theme)
    }

    func settingsPrimaryActionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.02, green: 0.48, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.55, green: 0.38, blue: 0.14, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.55, blue: 1, alpha: 1)
        }
    }

    func settingsPrimaryActionBorderColor(for theme: ReaderTheme) -> NSColor {
        settingsPrimaryActionBackgroundColor(for: theme)
    }

    func settingsPrimaryActionTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original, .dark:
            return .white
        case .eyeCare:
            return NSColor(red: 0.97, green: 0.93, blue: 0.78, alpha: 1)
        }
    }

    func settingsPanelBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func settingsFieldBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.87, green: 0.82, blue: 0.67, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    func settingsPanelBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.78, green: 0.82, blue: 0.90, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 1)
        }
    }

    func settingsSecondaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.45, green: 0.39, blue: 0.27, alpha: 1)
        case .dark:
            return NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
    }
}

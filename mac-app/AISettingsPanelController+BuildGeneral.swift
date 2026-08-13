import Cocoa

struct AISettingsPanelPalette {
    let background: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor

    init(theme: ReaderTheme) {
        switch theme {
        case .original:
            background = .white
            primaryText = NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
            secondaryText = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        case .eyeCare:
            background = NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
            primaryText = NSColor(red: 0.15, green: 0.13, blue: 0.09, alpha: 1)
            secondaryText = NSColor(red: 0.45, green: 0.39, blue: 0.27, alpha: 1)
        case .dark:
            background = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            primaryText = NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            secondaryText = NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }
    }
}

struct AISettingsGeneralSection {
    let languageLabel: NSTextField
    let languagePopup: NSPopUpButton
    let languageHelpLabel: NSTextField
    let themeLabel: NSTextField
    let themePopup: NSPopUpButton
    let themeHelpLabel: NSTextField
    let pdfDimmingLabel: NSTextField
    let pdfDimmingSlider: ThemedSettingsSlider
    let speakSelectedWordLabel: NSTextField
    let speakSelectedWordCheckbox: NSButton
    let saveAIConversationLabel: NSTextField
    let saveAIConversationCheckbox: NSButton

    var pageViews: [NSView] {
        [
            languageLabel, languagePopup, languageHelpLabel,
            themeLabel, themePopup, themeHelpLabel,
            pdfDimmingLabel, pdfDimmingSlider,
            speakSelectedWordLabel, speakSelectedWordCheckbox,
            saveAIConversationLabel, saveAIConversationCheckbox
        ]
    }
}

struct AISettingsGeneralLayout {
    let constraints: [NSLayoutConstraint]
    let pdfDimmingLabelTop: NSLayoutConstraint
    let speakSelectedWordTopToDimming: NSLayoutConstraint
    let speakSelectedWordTopToTheme: NSLayoutConstraint
    let pdfDimmingCollapsed: [NSLayoutConstraint]
}

extension AISettingsPanelController {
    func makeGeneralSection(
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        secondaryText: NSColor,
        theme: ReaderTheme
    ) -> AISettingsGeneralSection {
        let languageLabel = label(AppText.language, size: settingsFontSize, weight: .semibold, color: primaryText)
        let languageHelpLabel = label(AppText.languageHelp, size: settingsFontSize, color: secondaryText)
        languageHelpLabel.isHidden = true
        let languagePopup = popup(
            items: AppText.Language.allCases.map { ($0.title, $0.rawValue) },
            selected: AppText.selectedLanguage.rawValue,
            fontSize: settingsFontSize
        )
        languagePopup.identifier = Identifiers.languagePopup

        let themeLabel = label(AppText.localized("模式", "Mode"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let themeHelpLabel = label(ReaderTheme.selected.helpText, size: settingsFontSize, color: secondaryText)
        themeHelpLabel.isHidden = true
        let themePopup = popup(
            items: ReaderTheme.allCases.map { ($0.title, $0.rawValue) },
            selected: ReaderTheme.selected.rawValue,
            fontSize: settingsFontSize
        )
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        themePopup.identifier = Identifiers.themePopup

        let pdfDimmingLabel = label(AppText.localized("阅读区亮度", "Reading Area Brightness"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let pdfDimmingSlider = ThemedSettingsSlider(
            value: pdfBrightnessSliderValue(forDimmingStrength: ReaderTheme.pdfDimmingStrength),
            minValue: 0,
            maxValue: Self.pdfBrightnessSliderMaximum
        )
        pdfDimmingSlider.theme = theme
        pdfDimmingSlider.numberOfTickMarks = 7
        pdfDimmingSlider.target = self
        pdfDimmingSlider.action = #selector(pdfDimmingSliderChanged(_:))
        pdfDimmingSlider.translatesAutoresizingMaskIntoConstraints = false

        let speakSelectedWordLabel = label(AppText.localized("自动播放单词", "Auto Play Words"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speakSelectedWordCheckbox = settingsCheckbox(isOn: AISettingsStore.speakSelectedWordEnabled, theme: theme, fontSize: settingsFontSize)
        let saveAIConversationLabel = label(AppText.localized("保存 AI 对话信息", "Save AI Chat"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let saveAIConversationCheckbox = settingsCheckbox(isOn: AISettingsStore.saveAIConversationEnabled, theme: theme, fontSize: settingsFontSize)

        return AISettingsGeneralSection(
            languageLabel: languageLabel,
            languagePopup: languagePopup,
            languageHelpLabel: languageHelpLabel,
            themeLabel: themeLabel,
            themePopup: themePopup,
            themeHelpLabel: themeHelpLabel,
            pdfDimmingLabel: pdfDimmingLabel,
            pdfDimmingSlider: pdfDimmingSlider,
            speakSelectedWordLabel: speakSelectedWordLabel,
            speakSelectedWordCheckbox: speakSelectedWordCheckbox,
            saveAIConversationLabel: saveAIConversationLabel,
            saveAIConversationCheckbox: saveAIConversationCheckbox
        )
    }

    func generalConstraints(
        for section: AISettingsGeneralSection,
        page: NSView,
        labelColumnWidth: CGFloat,
        fieldWidth: CGFloat,
        controlHeight: CGFloat
    ) -> AISettingsGeneralLayout {
        let pdfDimmingLabelTop = section.pdfDimmingLabel.topAnchor.constraint(equalTo: section.themePopup.bottomAnchor, constant: 22)
        let speakSelectedWordTopToDimming = section.speakSelectedWordLabel.topAnchor.constraint(equalTo: section.pdfDimmingSlider.bottomAnchor, constant: 22)
        let speakSelectedWordTopToTheme = section.speakSelectedWordLabel.topAnchor.constraint(equalTo: section.themePopup.bottomAnchor, constant: 22)
        let pdfDimmingCollapsed = [
            section.pdfDimmingLabel.heightAnchor.constraint(equalToConstant: 0),
            section.pdfDimmingSlider.heightAnchor.constraint(equalToConstant: 0)
        ]
        let constraints = [
            section.languageLabel.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.languageLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.languageLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.languagePopup.topAnchor.constraint(equalTo: section.languageLabel.topAnchor),
            section.languagePopup.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.languagePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.languagePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.languageHelpLabel.topAnchor.constraint(equalTo: section.languagePopup.bottomAnchor, constant: 4),
            section.languageHelpLabel.leadingAnchor.constraint(equalTo: section.languagePopup.leadingAnchor),
            section.languageHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.themeLabel.topAnchor.constraint(equalTo: section.languagePopup.bottomAnchor, constant: 34),
            section.themeLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.themeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.themePopup.topAnchor.constraint(equalTo: section.themeLabel.topAnchor),
            section.themePopup.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.themePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.themePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.themeHelpLabel.topAnchor.constraint(equalTo: section.themePopup.bottomAnchor, constant: 4),
            section.themeHelpLabel.leadingAnchor.constraint(equalTo: section.themePopup.leadingAnchor),
            section.themeHelpLabel.widthAnchor.constraint(equalToConstant: fieldWidth),
            pdfDimmingLabelTop,
            section.pdfDimmingLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.pdfDimmingLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.pdfDimmingSlider.centerYAnchor.constraint(equalTo: section.pdfDimmingLabel.centerYAnchor),
            section.pdfDimmingSlider.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.pdfDimmingSlider.widthAnchor.constraint(equalToConstant: fieldWidth),
            speakSelectedWordTopToDimming,
            section.speakSelectedWordLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.speakSelectedWordLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.speakSelectedWordCheckbox.centerYAnchor.constraint(equalTo: section.speakSelectedWordLabel.centerYAnchor),
            section.speakSelectedWordCheckbox.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.speakSelectedWordCheckbox.widthAnchor.constraint(equalToConstant: 32),
            section.saveAIConversationLabel.topAnchor.constraint(equalTo: section.speakSelectedWordLabel.bottomAnchor, constant: 22),
            section.saveAIConversationLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.saveAIConversationLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.saveAIConversationCheckbox.centerYAnchor.constraint(equalTo: section.saveAIConversationLabel.centerYAnchor),
            section.saveAIConversationCheckbox.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.saveAIConversationCheckbox.widthAnchor.constraint(equalToConstant: 32),
            section.saveAIConversationCheckbox.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -8)
        ]
        return AISettingsGeneralLayout(
            constraints: constraints,
            pdfDimmingLabelTop: pdfDimmingLabelTop,
            speakSelectedWordTopToDimming: speakSelectedWordTopToDimming,
            speakSelectedWordTopToTheme: speakSelectedWordTopToTheme,
            pdfDimmingCollapsed: pdfDimmingCollapsed
        )
    }
}

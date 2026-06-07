import Cocoa

struct SpeechRuntimeRowControls {
    let runtime: SpeechRuntimeResourceManager.Runtime
    let card: NSView
    let titleLabel: NSTextField
    let statusLabel: NSTextField
    let progressIndicator: NSProgressIndicator
    let downloadButton: NSButton
    let pauseButton: NSButton
    let cancelButton: NSButton
    let deleteButton: NSButton

    var pageViews: [NSView] {
        [
            card,
            titleLabel,
            statusLabel,
            progressIndicator,
            downloadButton,
            pauseButton,
            cancelButton,
            deleteButton
        ]
    }
}

struct AISettingsSpeechSection {
    let runtimePopup: NSPopUpButton
    let voicePopup: NSPopUpButton
    let speedPopup: NSPopUpButton
    let runtimeRows: [SpeechRuntimeRowControls]
    let pageViews: [NSView]

    fileprivate let controlsContainer: NSView
    fileprivate let runtimeLabel: NSTextField
    fileprivate let voiceLabel: NSTextField
    fileprivate let speedLabel: NSTextField

    func controls(for runtime: SpeechRuntimeResourceManager.Runtime) -> SpeechRuntimeRowControls? {
        runtimeRows.first { $0.runtime == runtime }
    }
}

extension AISettingsPanelController {
    func makeSpeechSection(
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        secondaryText: NSColor
    ) -> AISettingsSpeechSection {
        let runtimeLabel = label(AppText.localized("朗读模型", "TTS Model"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let languageHint = currentSpeechLanguageHint?()
        syncSpeechRuntimeForLanguageIfNeeded(languageHint: languageHint)
        let runtimeID = effectiveSelectedSpeechRuntimeID(languageHint: languageHint)
        let runtimePopup = popup(
            items: SpeechRuntimeResourceManager.Runtime.displayOrder.map { ($0.title, $0.id) },
            selected: runtimeID,
            fontSize: settingsFontSize
        )
        runtimePopup.target = self
        runtimePopup.action = #selector(speechRuntimeChanged(_:))

        let voiceLabel = label(AppText.localized("声音", "Voice"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let voicePopup = popup(
            items: AISettingsStore.speechVoiceOptions(runtimeID: runtimeID, languageHint: languageHint).map { ($0.title, $0.id) },
            selected: AISettingsStore.selectedSpeechVoiceID(runtimeID: runtimeID),
            fontSize: settingsFontSize
        )
        voicePopup.target = self
        voicePopup.action = #selector(speechVoiceChanged(_:))

        let speedLabel = label(AppText.localized("语速", "Speed"), size: settingsFontSize, weight: .semibold, color: primaryText)
        let speedPopup = popup(
            items: AISettingsStore.speechSpeedOptions.map { ($0.title, $0.id) },
            selected: AISettingsStore.selectedSpeechSpeedID,
            fontSize: settingsFontSize
        )
        speedPopup.target = self
        speedPopup.action = #selector(speechSpeedChanged(_:))
        for fieldLabel in [runtimeLabel, voiceLabel, speedLabel] {
            fieldLabel.setContentHuggingPriority(.required, for: .vertical)
            fieldLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            fieldLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let controlsContainer = NSView()
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        for view in [runtimeLabel, runtimePopup, voiceLabel, voicePopup, speedLabel, speedPopup] {
            controlsContainer.addSubview(view)
        }

        let runtimeRows = SpeechRuntimeResourceManager.Runtime.displayOrder.map {
            makeSpeechRuntimeRow(runtime: $0, settingsFontSize: settingsFontSize, primaryText: primaryText, secondaryText: secondaryText)
        }
        runtimeRows.forEach { configureSpeechRuntimeRowState($0) }

        let pageViews = [controlsContainer] + runtimeRows.flatMap(\.pageViews)
        return AISettingsSpeechSection(
            runtimePopup: runtimePopup,
            voicePopup: voicePopup,
            speedPopup: speedPopup,
            runtimeRows: runtimeRows,
            pageViews: pageViews,
            controlsContainer: controlsContainer,
            runtimeLabel: runtimeLabel,
            voiceLabel: voiceLabel,
            speedLabel: speedLabel
        )
    }

    private func makeSpeechRuntimeRow(
        runtime: SpeechRuntimeResourceManager.Runtime,
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        secondaryText: NSColor
    ) -> SpeechRuntimeRowControls {
        let card = settingsSpeechRowCard()
        let titleLabel = label(runtime.title, size: settingsFontSize, weight: .semibold, color: primaryText)
        let statusLabel = label(SpeechRuntimeResourceManager.statusText(for: runtime), size: settingsFontSize, color: secondaryText)
        let progressIndicator = speechDownloadProgressIndicator()
        let downloadButton = settingsActionButton(
            title: AppText.localized("下载 \(runtime.title)", "Download \(runtime.title)"),
            target: self,
            action: #selector(downloadSpeechRuntimeButton(_:))
        )
        let pauseButton = settingsActionButton(
            title: AppText.localized("暂停", "Pause"),
            target: self,
            action: #selector(pauseSpeechRuntimeDownloadButton(_:))
        )
        let cancelButton = settingsActionButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(cancelSpeechRuntimeDownloadButton(_:))
        )
        let deleteButton = settingsActionButton(
            title: AppText.localized("删除", "Delete"),
            target: self,
            action: #selector(deleteSpeechRuntimeButton(_:))
        )
        let tag = speechRuntimeButtonTag(for: runtime)
        for button in [downloadButton, pauseButton, cancelButton, deleteButton] {
            button.tag = tag
        }
        return SpeechRuntimeRowControls(
            runtime: runtime,
            card: card,
            titleLabel: titleLabel,
            statusLabel: statusLabel,
            progressIndicator: progressIndicator,
            downloadButton: downloadButton,
            pauseButton: pauseButton,
            cancelButton: cancelButton,
            deleteButton: deleteButton
        )
    }

    func speechConstraints(
        for section: AISettingsSpeechSection,
        page: NSView,
        labelColumnWidth: CGFloat,
        fieldWidth: CGFloat,
        controlHeight: CGFloat
    ) -> [NSLayoutConstraint] {
        let rowHeight: CGFloat = 46
        let rowGap: CGFloat = 6
        let rowInset: CGFloat = 14
        let rowButtonHeight: CGFloat = 32
        let runtimeNameWidth: CGFloat = 88
        let runtimeStatusWidth: CGFloat = 280
        let runtimeProgressGap: CGFloat = 8
        let runtimeProgressWidth: CGFloat = 120
        let downloadButtonWidth: CGFloat = 112
        let actionButtonWidth: CGFloat = 68
        let fieldLabelHeight: CGFloat = 22
        let controlsRowGap: CGFloat = 16
        let controlsColumnGap: CGFloat = 18
        let controlsHeight = controlHeight * 3 + controlsRowGap * 2
        var constraints: [NSLayoutConstraint] = [
            section.controlsContainer.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.controlsContainer.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.controlsContainer.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            section.controlsContainer.heightAnchor.constraint(equalToConstant: controlsHeight),

            section.runtimePopup.topAnchor.constraint(equalTo: section.controlsContainer.topAnchor),
            section.runtimePopup.leadingAnchor.constraint(equalTo: section.controlsContainer.leadingAnchor, constant: labelColumnWidth + controlsColumnGap),
            section.runtimePopup.trailingAnchor.constraint(equalTo: section.controlsContainer.trailingAnchor),
            section.runtimePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.runtimeLabel.centerYAnchor.constraint(equalTo: section.runtimePopup.centerYAnchor),
            section.runtimeLabel.leadingAnchor.constraint(equalTo: section.controlsContainer.leadingAnchor),
            section.runtimeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.runtimeLabel.heightAnchor.constraint(equalToConstant: fieldLabelHeight),

            section.voicePopup.topAnchor.constraint(equalTo: section.runtimePopup.bottomAnchor, constant: controlsRowGap),
            section.voicePopup.leadingAnchor.constraint(equalTo: section.runtimePopup.leadingAnchor),
            section.voicePopup.trailingAnchor.constraint(equalTo: section.runtimePopup.trailingAnchor),
            section.voicePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.voiceLabel.centerYAnchor.constraint(equalTo: section.voicePopup.centerYAnchor),
            section.voiceLabel.leadingAnchor.constraint(equalTo: section.runtimeLabel.leadingAnchor),
            section.voiceLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.voiceLabel.heightAnchor.constraint(equalToConstant: fieldLabelHeight),

            section.speedPopup.topAnchor.constraint(equalTo: section.voicePopup.bottomAnchor, constant: controlsRowGap),
            section.speedPopup.leadingAnchor.constraint(equalTo: section.runtimePopup.leadingAnchor),
            section.speedPopup.trailingAnchor.constraint(equalTo: section.runtimePopup.trailingAnchor),
            section.speedPopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.speedLabel.centerYAnchor.constraint(equalTo: section.speedPopup.centerYAnchor),
            section.speedLabel.leadingAnchor.constraint(equalTo: section.runtimeLabel.leadingAnchor),
            section.speedLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.speedLabel.heightAnchor.constraint(equalToConstant: fieldLabelHeight)
        ]

        for (index, row) in section.runtimeRows.enumerated() {
            if index == 0 {
                constraints += [
                    row.card.topAnchor.constraint(equalTo: section.controlsContainer.bottomAnchor, constant: 22),
                    row.card.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                    row.card.trailingAnchor.constraint(equalTo: page.trailingAnchor)
                ]
            } else {
                let previous = section.runtimeRows[index - 1]
                constraints += [
                    row.card.topAnchor.constraint(equalTo: previous.card.bottomAnchor, constant: rowGap),
                    row.card.leadingAnchor.constraint(equalTo: previous.card.leadingAnchor),
                    row.card.trailingAnchor.constraint(equalTo: previous.card.trailingAnchor)
                ]
            }
            constraints += runtimeRowConstraints(
                row,
                rowHeight: rowHeight,
                rowInset: rowInset,
                rowButtonHeight: rowButtonHeight,
                runtimeNameWidth: runtimeNameWidth,
                runtimeStatusWidth: runtimeStatusWidth,
                runtimeProgressGap: runtimeProgressGap,
                runtimeProgressWidth: runtimeProgressWidth,
                downloadButtonWidth: downloadButtonWidth,
                actionButtonWidth: actionButtonWidth
            )
        }
        if let lastRow = section.runtimeRows.last {
            constraints.append(lastRow.card.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -8))
        }
        return constraints
    }

    private func runtimeRowConstraints(
        _ row: SpeechRuntimeRowControls,
        rowHeight: CGFloat,
        rowInset: CGFloat,
        rowButtonHeight: CGFloat,
        runtimeNameWidth: CGFloat,
        runtimeStatusWidth: CGFloat,
        runtimeProgressGap: CGFloat,
        runtimeProgressWidth: CGFloat,
        downloadButtonWidth: CGFloat,
        actionButtonWidth: CGFloat
    ) -> [NSLayoutConstraint] {
        [
            row.card.heightAnchor.constraint(equalToConstant: rowHeight),
            row.titleLabel.centerYAnchor.constraint(equalTo: row.card.centerYAnchor),
            row.titleLabel.leadingAnchor.constraint(equalTo: row.card.leadingAnchor, constant: rowInset),
            row.titleLabel.widthAnchor.constraint(equalToConstant: runtimeNameWidth),
            row.statusLabel.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
            row.statusLabel.leadingAnchor.constraint(equalTo: row.titleLabel.trailingAnchor, constant: 12),
            row.statusLabel.widthAnchor.constraint(equalToConstant: runtimeStatusWidth),
            row.progressIndicator.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
            row.progressIndicator.leadingAnchor.constraint(equalTo: row.statusLabel.trailingAnchor, constant: runtimeProgressGap),
            row.progressIndicator.widthAnchor.constraint(lessThanOrEqualToConstant: runtimeProgressWidth),
            row.progressIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            row.progressIndicator.trailingAnchor.constraint(lessThanOrEqualTo: row.pauseButton.leadingAnchor, constant: -8),
            row.progressIndicator.heightAnchor.constraint(equalToConstant: 8),
            row.downloadButton.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
            row.downloadButton.trailingAnchor.constraint(equalTo: row.card.trailingAnchor, constant: -rowInset),
            row.downloadButton.widthAnchor.constraint(equalToConstant: downloadButtonWidth),
            row.downloadButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            row.pauseButton.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
            row.pauseButton.trailingAnchor.constraint(equalTo: row.cancelButton.leadingAnchor, constant: -8),
            row.pauseButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            row.pauseButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            row.cancelButton.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
            row.cancelButton.trailingAnchor.constraint(equalTo: row.card.trailingAnchor, constant: -rowInset),
            row.cancelButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            row.cancelButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            row.deleteButton.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
            row.deleteButton.trailingAnchor.constraint(equalTo: row.card.trailingAnchor, constant: -rowInset),
            row.deleteButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            row.deleteButton.heightAnchor.constraint(equalToConstant: rowButtonHeight)
        ]
    }

    private func configureSpeechRuntimeRowState(_ row: SpeechRuntimeRowControls) {
        let isDownloaded = SpeechRuntimeResourceManager.isDownloaded(row.runtime)
        let isDownloading = SpeechRuntimeResourceManager.isDownloading(row.runtime)
        row.deleteButton.isEnabled = isDownloaded
        row.progressIndicator.isHidden = !isDownloading
        row.downloadButton.isHidden = isDownloaded || isDownloading
        row.pauseButton.isHidden = !isDownloading
        row.cancelButton.isHidden = !isDownloading
        row.deleteButton.isHidden = !isDownloaded
    }
}

import Cocoa

struct AISettingsSpeechSection {
    let runtimePopup: NSPopUpButton
    let voicePopup: NSPopUpButton
    let speedPopup: NSPopUpButton
    let kokoroStatusLabel: NSTextField
    let kittenStatusLabel: NSTextField
    let piperStatusLabel: NSTextField
    let kokoroProgressIndicator: NSProgressIndicator
    let kittenProgressIndicator: NSProgressIndicator
    let piperProgressIndicator: NSProgressIndicator
    let kokoroDownloadButton: NSButton
    let kittenDownloadButton: NSButton
    let piperDownloadButton: NSButton
    let kokoroPauseButton: NSButton
    let kittenPauseButton: NSButton
    let piperPauseButton: NSButton
    let kokoroCancelButton: NSButton
    let kittenCancelButton: NSButton
    let piperCancelButton: NSButton
    let kokoroDeleteButton: NSButton
    let kittenDeleteButton: NSButton
    let piperDeleteButton: NSButton
    let pageViews: [NSView]

    fileprivate let titleLabel: NSTextField
    fileprivate let runtimeLabel: NSTextField
    fileprivate let voiceLabel: NSTextField
    fileprivate let speedLabel: NSTextField
    fileprivate let kokoroCard: NSView
    fileprivate let kittenCard: NSView
    fileprivate let piperCard: NSView
    fileprivate let kokoroLabel: NSTextField
    fileprivate let kittenLabel: NSTextField
    fileprivate let piperLabel: NSTextField
}

extension AISettingsPanelController {
    func makeSpeechSection(
        settingsFontSize: CGFloat,
        primaryText: NSColor,
        secondaryText: NSColor
    ) -> AISettingsSpeechSection {
        let titleLabel = label(AppText.localized("朗读", "Read Aloud"), size: settingsFontSize, weight: .semibold, color: primaryText)
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

        let kokoroCard = settingsSpeechRowCard()
        let kittenCard = settingsSpeechRowCard()
        let piperCard = settingsSpeechRowCard()
        let kokoroLabel = label("Kokoro", size: settingsFontSize, weight: .semibold, color: primaryText)
        let kokoroStatusLabel = label(SpeechRuntimeResourceManager.statusText(for: .kokoro), size: settingsFontSize, color: secondaryText)
        let kokoroProgressIndicator = speechDownloadProgressIndicator()
        let kokoroDownloadButton = settingsActionButton(
            title: AppText.localized("下载 Kokoro", "Download Kokoro"),
            target: self,
            action: #selector(downloadKokoroSpeechRuntime(_:))
        )
        let kokoroPauseButton = settingsActionButton(
            title: AppText.localized("暂停", "Pause"),
            target: self,
            action: #selector(pauseKokoroSpeechRuntimeDownload(_:))
        )
        let kokoroCancelButton = settingsActionButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(cancelKokoroSpeechRuntimeDownload(_:))
        )
        let kokoroDeleteButton = settingsActionButton(
            title: AppText.localized("删除", "Delete"),
            target: self,
            action: #selector(deleteKokoroSpeechRuntime(_:))
        )

        let kittenLabel = label("KittenTTS", size: settingsFontSize, weight: .semibold, color: primaryText)
        let kittenStatusLabel = label(SpeechRuntimeResourceManager.statusText(for: .kitten), size: settingsFontSize, color: secondaryText)
        let kittenProgressIndicator = speechDownloadProgressIndicator()
        let kittenDownloadButton = settingsActionButton(
            title: AppText.localized("下载 Kitten", "Download Kitten"),
            target: self,
            action: #selector(downloadKittenSpeechRuntime(_:))
        )
        let kittenPauseButton = settingsActionButton(
            title: AppText.localized("暂停", "Pause"),
            target: self,
            action: #selector(pauseKittenSpeechRuntimeDownload(_:))
        )
        let kittenCancelButton = settingsActionButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(cancelKittenSpeechRuntimeDownload(_:))
        )
        let kittenDeleteButton = settingsActionButton(
            title: AppText.localized("删除", "Delete"),
            target: self,
            action: #selector(deleteKittenSpeechRuntime(_:))
        )

        let piperLabel = label("Piper", size: settingsFontSize, weight: .semibold, color: primaryText)
        let piperStatusLabel = label(SpeechRuntimeResourceManager.statusText(for: .piper), size: settingsFontSize, color: secondaryText)
        let piperProgressIndicator = speechDownloadProgressIndicator()
        let piperDownloadButton = settingsActionButton(
            title: AppText.localized("下载 Piper", "Download Piper"),
            target: self,
            action: #selector(downloadPiperSpeechRuntime(_:))
        )
        let piperPauseButton = settingsActionButton(
            title: AppText.localized("暂停", "Pause"),
            target: self,
            action: #selector(pausePiperSpeechRuntimeDownload(_:))
        )
        let piperCancelButton = settingsActionButton(
            title: AppText.localized("取消", "Cancel"),
            target: self,
            action: #selector(cancelPiperSpeechRuntimeDownload(_:))
        )
        let piperDeleteButton = settingsActionButton(
            title: AppText.localized("删除", "Delete"),
            target: self,
            action: #selector(deletePiperSpeechRuntime(_:))
        )

        configureSpeechRuntimeRowState(
            runtime: .kokoro,
            progressIndicator: kokoroProgressIndicator,
            downloadButton: kokoroDownloadButton,
            pauseButton: kokoroPauseButton,
            cancelButton: kokoroCancelButton,
            deleteButton: kokoroDeleteButton
        )
        configureSpeechRuntimeRowState(
            runtime: .kitten,
            progressIndicator: kittenProgressIndicator,
            downloadButton: kittenDownloadButton,
            pauseButton: kittenPauseButton,
            cancelButton: kittenCancelButton,
            deleteButton: kittenDeleteButton
        )
        configureSpeechRuntimeRowState(
            runtime: .piper,
            progressIndicator: piperProgressIndicator,
            downloadButton: piperDownloadButton,
            pauseButton: piperPauseButton,
            cancelButton: piperCancelButton,
            deleteButton: piperDeleteButton
        )

        let pageViews: [NSView] = [
            titleLabel, runtimeLabel, runtimePopup, voiceLabel, voicePopup, speedLabel, speedPopup,
            kokoroCard, kittenCard, piperCard,
            kokoroLabel, kokoroStatusLabel, kokoroProgressIndicator,
            kokoroDownloadButton, kokoroPauseButton, kokoroCancelButton, kokoroDeleteButton,
            kittenLabel, kittenStatusLabel, kittenProgressIndicator,
            kittenDownloadButton, kittenPauseButton, kittenCancelButton, kittenDeleteButton,
            piperLabel, piperStatusLabel, piperProgressIndicator,
            piperDownloadButton, piperPauseButton, piperCancelButton, piperDeleteButton
        ]

        return AISettingsSpeechSection(
            runtimePopup: runtimePopup,
            voicePopup: voicePopup,
            speedPopup: speedPopup,
            kokoroStatusLabel: kokoroStatusLabel,
            kittenStatusLabel: kittenStatusLabel,
            piperStatusLabel: piperStatusLabel,
            kokoroProgressIndicator: kokoroProgressIndicator,
            kittenProgressIndicator: kittenProgressIndicator,
            piperProgressIndicator: piperProgressIndicator,
            kokoroDownloadButton: kokoroDownloadButton,
            kittenDownloadButton: kittenDownloadButton,
            piperDownloadButton: piperDownloadButton,
            kokoroPauseButton: kokoroPauseButton,
            kittenPauseButton: kittenPauseButton,
            piperPauseButton: piperPauseButton,
            kokoroCancelButton: kokoroCancelButton,
            kittenCancelButton: kittenCancelButton,
            piperCancelButton: piperCancelButton,
            kokoroDeleteButton: kokoroDeleteButton,
            kittenDeleteButton: kittenDeleteButton,
            piperDeleteButton: piperDeleteButton,
            pageViews: pageViews,
            titleLabel: titleLabel,
            runtimeLabel: runtimeLabel,
            voiceLabel: voiceLabel,
            speedLabel: speedLabel,
            kokoroCard: kokoroCard,
            kittenCard: kittenCard,
            piperCard: piperCard,
            kokoroLabel: kokoroLabel,
            kittenLabel: kittenLabel,
            piperLabel: piperLabel
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
        return [
            section.titleLabel.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.titleLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.titleLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.runtimeLabel.topAnchor.constraint(equalTo: section.titleLabel.topAnchor),
            section.runtimeLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.runtimeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.runtimePopup.centerYAnchor.constraint(equalTo: section.runtimeLabel.centerYAnchor),
            section.runtimePopup.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.runtimePopup.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            section.runtimePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.voiceLabel.topAnchor.constraint(equalTo: section.runtimePopup.bottomAnchor, constant: 16),
            section.voiceLabel.leadingAnchor.constraint(equalTo: section.runtimeLabel.leadingAnchor),
            section.voiceLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.voicePopup.centerYAnchor.constraint(equalTo: section.voiceLabel.centerYAnchor),
            section.voicePopup.leadingAnchor.constraint(equalTo: section.runtimePopup.leadingAnchor),
            section.voicePopup.trailingAnchor.constraint(equalTo: section.runtimePopup.trailingAnchor),
            section.voicePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.speedLabel.topAnchor.constraint(equalTo: section.voicePopup.bottomAnchor, constant: 16),
            section.speedLabel.leadingAnchor.constraint(equalTo: section.runtimeLabel.leadingAnchor),
            section.speedLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.speedPopup.centerYAnchor.constraint(equalTo: section.speedLabel.centerYAnchor),
            section.speedPopup.leadingAnchor.constraint(equalTo: section.runtimePopup.leadingAnchor),
            section.speedPopup.trailingAnchor.constraint(equalTo: section.runtimePopup.trailingAnchor),
            section.speedPopup.heightAnchor.constraint(equalToConstant: controlHeight),

            section.kittenCard.topAnchor.constraint(equalTo: section.speedPopup.bottomAnchor, constant: 18),
            section.kittenCard.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.kittenCard.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            section.kittenCard.heightAnchor.constraint(equalToConstant: rowHeight),
            section.piperCard.topAnchor.constraint(equalTo: section.kittenCard.bottomAnchor, constant: rowGap),
            section.piperCard.leadingAnchor.constraint(equalTo: section.kittenCard.leadingAnchor),
            section.piperCard.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor),
            section.piperCard.heightAnchor.constraint(equalToConstant: rowHeight),
            section.kokoroCard.topAnchor.constraint(equalTo: section.piperCard.bottomAnchor, constant: rowGap),
            section.kokoroCard.leadingAnchor.constraint(equalTo: section.kittenCard.leadingAnchor),
            section.kokoroCard.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor),
            section.kokoroCard.heightAnchor.constraint(equalToConstant: rowHeight),

            section.kokoroLabel.centerYAnchor.constraint(equalTo: section.kokoroCard.centerYAnchor),
            section.kokoroLabel.leadingAnchor.constraint(equalTo: section.kokoroCard.leadingAnchor, constant: rowInset),
            section.kokoroLabel.widthAnchor.constraint(equalToConstant: runtimeNameWidth),
            section.kokoroStatusLabel.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroStatusLabel.leadingAnchor.constraint(equalTo: section.kokoroLabel.trailingAnchor, constant: 12),
            section.kokoroStatusLabel.widthAnchor.constraint(equalToConstant: runtimeStatusWidth),
            section.kokoroProgressIndicator.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroProgressIndicator.leadingAnchor.constraint(equalTo: section.kokoroStatusLabel.trailingAnchor, constant: runtimeProgressGap),
            section.kokoroProgressIndicator.widthAnchor.constraint(equalToConstant: runtimeProgressWidth),
            section.kokoroProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            section.kokoroDownloadButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroDownloadButton.trailingAnchor.constraint(equalTo: section.kokoroCard.trailingAnchor, constant: -rowInset),
            section.kokoroDownloadButton.widthAnchor.constraint(equalToConstant: downloadButtonWidth),
            section.kokoroDownloadButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kokoroPauseButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroPauseButton.trailingAnchor.constraint(equalTo: section.kokoroCancelButton.leadingAnchor, constant: -8),
            section.kokoroPauseButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.kokoroPauseButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kokoroCancelButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroCancelButton.trailingAnchor.constraint(equalTo: section.kokoroCard.trailingAnchor, constant: -rowInset),
            section.kokoroCancelButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.kokoroCancelButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kokoroDeleteButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroDeleteButton.trailingAnchor.constraint(equalTo: section.kokoroCard.trailingAnchor, constant: -rowInset),
            section.kokoroDeleteButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.kokoroDeleteButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),

            section.kittenLabel.centerYAnchor.constraint(equalTo: section.kittenCard.centerYAnchor),
            section.kittenLabel.leadingAnchor.constraint(equalTo: section.kokoroLabel.leadingAnchor),
            section.kittenLabel.widthAnchor.constraint(equalToConstant: runtimeNameWidth),
            section.kittenStatusLabel.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenStatusLabel.leadingAnchor.constraint(equalTo: section.kittenLabel.trailingAnchor, constant: 12),
            section.kittenStatusLabel.widthAnchor.constraint(equalToConstant: runtimeStatusWidth),
            section.kittenProgressIndicator.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenProgressIndicator.leadingAnchor.constraint(equalTo: section.kittenStatusLabel.trailingAnchor, constant: runtimeProgressGap),
            section.kittenProgressIndicator.widthAnchor.constraint(equalToConstant: runtimeProgressWidth),
            section.kittenProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            section.kittenDownloadButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenDownloadButton.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor, constant: -rowInset),
            section.kittenDownloadButton.widthAnchor.constraint(equalToConstant: downloadButtonWidth),
            section.kittenDownloadButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kittenPauseButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenPauseButton.trailingAnchor.constraint(equalTo: section.kittenCancelButton.leadingAnchor, constant: -8),
            section.kittenPauseButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.kittenPauseButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kittenCancelButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenCancelButton.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor, constant: -rowInset),
            section.kittenCancelButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.kittenCancelButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kittenDeleteButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenDeleteButton.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor, constant: -rowInset),
            section.kittenDeleteButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.kittenDeleteButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),

            section.piperLabel.centerYAnchor.constraint(equalTo: section.piperCard.centerYAnchor),
            section.piperLabel.leadingAnchor.constraint(equalTo: section.kokoroLabel.leadingAnchor),
            section.piperLabel.widthAnchor.constraint(equalToConstant: runtimeNameWidth),
            section.piperStatusLabel.centerYAnchor.constraint(equalTo: section.piperLabel.centerYAnchor),
            section.piperStatusLabel.leadingAnchor.constraint(equalTo: section.piperLabel.trailingAnchor, constant: 12),
            section.piperStatusLabel.widthAnchor.constraint(equalToConstant: runtimeStatusWidth),
            section.piperProgressIndicator.centerYAnchor.constraint(equalTo: section.piperLabel.centerYAnchor),
            section.piperProgressIndicator.leadingAnchor.constraint(equalTo: section.piperStatusLabel.trailingAnchor, constant: runtimeProgressGap),
            section.piperProgressIndicator.widthAnchor.constraint(equalToConstant: runtimeProgressWidth),
            section.piperProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            section.piperDownloadButton.centerYAnchor.constraint(equalTo: section.piperLabel.centerYAnchor),
            section.piperDownloadButton.trailingAnchor.constraint(equalTo: section.piperCard.trailingAnchor, constant: -rowInset),
            section.piperDownloadButton.widthAnchor.constraint(equalToConstant: downloadButtonWidth),
            section.piperDownloadButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.piperPauseButton.centerYAnchor.constraint(equalTo: section.piperLabel.centerYAnchor),
            section.piperPauseButton.trailingAnchor.constraint(equalTo: section.piperCancelButton.leadingAnchor, constant: -8),
            section.piperPauseButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.piperPauseButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.piperCancelButton.centerYAnchor.constraint(equalTo: section.piperLabel.centerYAnchor),
            section.piperCancelButton.trailingAnchor.constraint(equalTo: section.piperCard.trailingAnchor, constant: -rowInset),
            section.piperCancelButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.piperCancelButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.piperDeleteButton.centerYAnchor.constraint(equalTo: section.piperLabel.centerYAnchor),
            section.piperDeleteButton.trailingAnchor.constraint(equalTo: section.piperCard.trailingAnchor, constant: -rowInset),
            section.piperDeleteButton.widthAnchor.constraint(equalToConstant: actionButtonWidth),
            section.piperDeleteButton.heightAnchor.constraint(equalToConstant: rowButtonHeight),
            section.kokoroCard.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -8)
        ]
    }

    private func configureSpeechRuntimeRowState(
        runtime: SpeechRuntimeResourceManager.Runtime,
        progressIndicator: NSProgressIndicator,
        downloadButton: NSButton,
        pauseButton: NSButton,
        cancelButton: NSButton,
        deleteButton: NSButton
    ) {
        let isDownloaded = SpeechRuntimeResourceManager.isDownloaded(runtime)
        let isDownloading = SpeechRuntimeResourceManager.isDownloading(runtime)
        deleteButton.isEnabled = isDownloaded
        progressIndicator.isHidden = !isDownloading
        downloadButton.isHidden = isDownloaded || isDownloading
        pauseButton.isHidden = !isDownloading
        cancelButton.isHidden = !isDownloading
        deleteButton.isHidden = !isDownloaded
    }
}

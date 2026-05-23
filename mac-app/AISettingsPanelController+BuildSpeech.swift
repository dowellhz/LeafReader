import Cocoa

struct AISettingsSpeechSection {
    let runtimePopup: NSPopUpButton
    let voicePopup: NSPopUpButton
    let speedPopup: NSPopUpButton
    let kokoroStatusLabel: NSTextField
    let kittenStatusLabel: NSTextField
    let kokoroProgressIndicator: NSProgressIndicator
    let kittenProgressIndicator: NSProgressIndicator
    let kokoroDownloadButton: NSButton
    let kittenDownloadButton: NSButton
    let kokoroPauseButton: NSButton
    let kittenPauseButton: NSButton
    let kokoroCancelButton: NSButton
    let kittenCancelButton: NSButton
    let kokoroDeleteButton: NSButton
    let kittenDeleteButton: NSButton
    let pageViews: [NSView]

    fileprivate let titleLabel: NSTextField
    fileprivate let runtimeLabel: NSTextField
    fileprivate let voiceLabel: NSTextField
    fileprivate let speedLabel: NSTextField
    fileprivate let kokoroCard: NSView
    fileprivate let kittenCard: NSView
    fileprivate let kokoroLabel: NSTextField
    fileprivate let kittenLabel: NSTextField
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

        let pageViews: [NSView] = [
            titleLabel, runtimeLabel, runtimePopup, voiceLabel, voicePopup, speedLabel, speedPopup,
            kokoroCard, kittenCard,
            kokoroLabel, kokoroStatusLabel, kokoroProgressIndicator,
            kokoroDownloadButton, kokoroPauseButton, kokoroCancelButton, kokoroDeleteButton,
            kittenLabel, kittenStatusLabel, kittenProgressIndicator,
            kittenDownloadButton, kittenPauseButton, kittenCancelButton, kittenDeleteButton
        ]

        return AISettingsSpeechSection(
            runtimePopup: runtimePopup,
            voicePopup: voicePopup,
            speedPopup: speedPopup,
            kokoroStatusLabel: kokoroStatusLabel,
            kittenStatusLabel: kittenStatusLabel,
            kokoroProgressIndicator: kokoroProgressIndicator,
            kittenProgressIndicator: kittenProgressIndicator,
            kokoroDownloadButton: kokoroDownloadButton,
            kittenDownloadButton: kittenDownloadButton,
            kokoroPauseButton: kokoroPauseButton,
            kittenPauseButton: kittenPauseButton,
            kokoroCancelButton: kokoroCancelButton,
            kittenCancelButton: kittenCancelButton,
            kokoroDeleteButton: kokoroDeleteButton,
            kittenDeleteButton: kittenDeleteButton,
            pageViews: pageViews,
            titleLabel: titleLabel,
            runtimeLabel: runtimeLabel,
            voiceLabel: voiceLabel,
            speedLabel: speedLabel,
            kokoroCard: kokoroCard,
            kittenCard: kittenCard,
            kokoroLabel: kokoroLabel,
            kittenLabel: kittenLabel
        )
    }

    func speechConstraints(
        for section: AISettingsSpeechSection,
        page: NSView,
        labelColumnWidth: CGFloat,
        fieldWidth: CGFloat,
        controlHeight: CGFloat
    ) -> [NSLayoutConstraint] {
        [
            section.titleLabel.topAnchor.constraint(equalTo: page.topAnchor, constant: 4),
            section.titleLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.titleLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.runtimeLabel.topAnchor.constraint(equalTo: section.titleLabel.topAnchor),
            section.runtimeLabel.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.runtimeLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.runtimePopup.centerYAnchor.constraint(equalTo: section.runtimeLabel.centerYAnchor),
            section.runtimePopup.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: labelColumnWidth),
            section.runtimePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.runtimePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.voiceLabel.topAnchor.constraint(equalTo: section.runtimePopup.bottomAnchor, constant: 16),
            section.voiceLabel.leadingAnchor.constraint(equalTo: section.runtimeLabel.leadingAnchor),
            section.voiceLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.voicePopup.centerYAnchor.constraint(equalTo: section.voiceLabel.centerYAnchor),
            section.voicePopup.leadingAnchor.constraint(equalTo: section.runtimePopup.leadingAnchor),
            section.voicePopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.voicePopup.heightAnchor.constraint(equalToConstant: controlHeight),
            section.speedLabel.topAnchor.constraint(equalTo: section.voicePopup.bottomAnchor, constant: 16),
            section.speedLabel.leadingAnchor.constraint(equalTo: section.runtimeLabel.leadingAnchor),
            section.speedLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth),
            section.speedPopup.centerYAnchor.constraint(equalTo: section.speedLabel.centerYAnchor),
            section.speedPopup.leadingAnchor.constraint(equalTo: section.runtimePopup.leadingAnchor),
            section.speedPopup.widthAnchor.constraint(equalToConstant: fieldWidth),
            section.speedPopup.heightAnchor.constraint(equalToConstant: controlHeight),

            section.kittenCard.topAnchor.constraint(equalTo: section.speedPopup.bottomAnchor, constant: 28),
            section.kittenCard.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            section.kittenCard.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            section.kittenCard.heightAnchor.constraint(equalToConstant: 58),
            section.kokoroCard.topAnchor.constraint(equalTo: section.kittenCard.bottomAnchor, constant: 10),
            section.kokoroCard.leadingAnchor.constraint(equalTo: section.kittenCard.leadingAnchor),
            section.kokoroCard.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor),
            section.kokoroCard.heightAnchor.constraint(equalToConstant: 58),

            section.kokoroLabel.centerYAnchor.constraint(equalTo: section.kokoroCard.centerYAnchor),
            section.kokoroLabel.leadingAnchor.constraint(equalTo: section.kokoroCard.leadingAnchor, constant: 16),
            section.kokoroLabel.widthAnchor.constraint(equalToConstant: 92),
            section.kokoroStatusLabel.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroStatusLabel.leadingAnchor.constraint(equalTo: section.kokoroLabel.trailingAnchor, constant: 16),
            section.kokoroStatusLabel.widthAnchor.constraint(equalToConstant: 126),
            section.kokoroProgressIndicator.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroProgressIndicator.leadingAnchor.constraint(equalTo: section.kokoroStatusLabel.trailingAnchor, constant: 12),
            section.kokoroProgressIndicator.widthAnchor.constraint(equalToConstant: 110),
            section.kokoroProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            section.kokoroDownloadButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroDownloadButton.trailingAnchor.constraint(equalTo: section.kokoroCard.trailingAnchor, constant: -16),
            section.kokoroDownloadButton.widthAnchor.constraint(equalToConstant: 124),
            section.kokoroDownloadButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.kokoroPauseButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroPauseButton.trailingAnchor.constraint(equalTo: section.kokoroCancelButton.leadingAnchor, constant: -8),
            section.kokoroPauseButton.widthAnchor.constraint(equalToConstant: 76),
            section.kokoroPauseButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.kokoroCancelButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroCancelButton.trailingAnchor.constraint(equalTo: section.kokoroCard.trailingAnchor, constant: -16),
            section.kokoroCancelButton.widthAnchor.constraint(equalToConstant: 76),
            section.kokoroCancelButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.kokoroDeleteButton.centerYAnchor.constraint(equalTo: section.kokoroLabel.centerYAnchor),
            section.kokoroDeleteButton.trailingAnchor.constraint(equalTo: section.kokoroCard.trailingAnchor, constant: -16),
            section.kokoroDeleteButton.widthAnchor.constraint(equalToConstant: 76),
            section.kokoroDeleteButton.heightAnchor.constraint(equalToConstant: controlHeight),

            section.kittenLabel.centerYAnchor.constraint(equalTo: section.kittenCard.centerYAnchor),
            section.kittenLabel.leadingAnchor.constraint(equalTo: section.kokoroLabel.leadingAnchor),
            section.kittenLabel.widthAnchor.constraint(equalToConstant: 92),
            section.kittenStatusLabel.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenStatusLabel.leadingAnchor.constraint(equalTo: section.kittenLabel.trailingAnchor, constant: 16),
            section.kittenStatusLabel.widthAnchor.constraint(equalToConstant: 126),
            section.kittenProgressIndicator.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenProgressIndicator.leadingAnchor.constraint(equalTo: section.kittenStatusLabel.trailingAnchor, constant: 12),
            section.kittenProgressIndicator.widthAnchor.constraint(equalToConstant: 110),
            section.kittenProgressIndicator.heightAnchor.constraint(equalToConstant: 8),
            section.kittenDownloadButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenDownloadButton.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor, constant: -16),
            section.kittenDownloadButton.widthAnchor.constraint(equalToConstant: 124),
            section.kittenDownloadButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.kittenPauseButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenPauseButton.trailingAnchor.constraint(equalTo: section.kittenCancelButton.leadingAnchor, constant: -8),
            section.kittenPauseButton.widthAnchor.constraint(equalToConstant: 76),
            section.kittenPauseButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.kittenCancelButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenCancelButton.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor, constant: -16),
            section.kittenCancelButton.widthAnchor.constraint(equalToConstant: 76),
            section.kittenCancelButton.heightAnchor.constraint(equalToConstant: controlHeight),
            section.kittenDeleteButton.centerYAnchor.constraint(equalTo: section.kittenLabel.centerYAnchor),
            section.kittenDeleteButton.trailingAnchor.constraint(equalTo: section.kittenCard.trailingAnchor, constant: -16),
            section.kittenDeleteButton.widthAnchor.constraint(equalToConstant: 76),
            section.kittenDeleteButton.heightAnchor.constraint(equalToConstant: controlHeight),
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

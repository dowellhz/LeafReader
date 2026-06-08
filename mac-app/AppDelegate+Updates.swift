import Cocoa
import Sparkle

extension AppDelegate {
    @objc func checkForUpdates(_ sender: Any?) {
        startUpdaterIfNeeded()
        guard let updater = updaterController?.updater else { return }
        guard updater.canCheckForUpdates else {
            showWhiteUpdateStatus(
                title: AppText.localized("正在检查更新", "Checking for Updates"),
                message: AppText.localized("Leaf Reader 正在处理更新，请稍后再试。", "Leaf Reader is already handling an update. Please try again shortly."),
                showsProgress: true
            )
            return
        }

        manualUpdateProbeInProgress = true
        manualUpdateProbeFoundUpdate = false
        manualUpdateProbeHandledResult = false
        manualUpdateSender = sender as AnyObject?
        showWhiteUpdateStatus(
            title: AppText.localized("正在检查更新", "Checking for Updates"),
            message: AppText.localized("正在连接 Leaf Reader 更新源...", "Connecting to the Leaf Reader update feed..."),
            showsProgress: true
        )
        updater.checkForUpdateInformation()
    }

    private func showWhiteUpdateStatus(title: String, message: String, showsProgress: Bool = false) {
        if let updateStatusWindow {
            updateStatusWindow.close()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.localized("Leaf Reader 更新", "Leaf Reader Updates")
        window.isReleasedWhenClosed = false
        window.center()

        let theme = ReaderTheme.selected
        let backgroundColor: NSColor
        let primaryText: NSColor
        let messageText: NSColor
        switch theme {
        case .original:
            backgroundColor = .white
            primaryText = .labelColor
            messageText = NSColor(red: 0.27, green: 0.29, blue: 0.33, alpha: 1)
        case .eyeCare:
            backgroundColor = NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
            primaryText = NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
            messageText = NSColor(red: 0.36, green: 0.31, blue: 0.21, alpha: 1)
        case .dark:
            backgroundColor = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            primaryText = NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            messageText = NSColor(red: 0.68, green: 0.73, blue: 0.80, alpha: 1)
        }

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = backgroundColor.cgColor
        window.contentView = content

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = primaryText
        content.addSubview(titleLabel)

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = messageText
        messageLabel.maximumNumberOfLines = 3
        content.addSubview(messageLabel)

        let progressIndicator = NSProgressIndicator()
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = true
        progressIndicator.isDisplayedWhenStopped = false
        if showsProgress {
            progressIndicator.startAnimation(nil)
        }
        progressIndicator.isHidden = !showsProgress
        content.addSubview(progressIndicator)

        let okButton = NSButton(title: AppText.confirm, target: self, action: #selector(closeUpdateStatusWindow(_:)))
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.bezelStyle = .rounded
        okButton.font = .systemFont(ofSize: 14, weight: .semibold)
        okButton.keyEquivalent = "\r"
        okButton.isHidden = showsProgress
        content.addSubview(okButton)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 70),
            iconView.heightAnchor.constraint(equalToConstant: 70),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            messageLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),

            progressIndicator.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -34),

            okButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            okButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            okButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            okButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        updateStatusWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeUpdateStatusWindow(_ sender: Any?) {
        updateStatusWindow?.close()
    }

    @objc private func updateStatusWindowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === updateStatusWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: updateStatusWindow)
        updateStatusWindow = nil
    }

    private func updateFailureMessage(from error: Error?) -> String {
        guard let nsError = error as NSError? else {
            return AppText.localized("暂时无法检查更新，请稍后再试。", "Unable to check for updates right now. Please try again later.")
        }

        switch UpdateFailureClassifier.classify(nsError) {
        case .certificate:
            return AppText.localized(
                "更新源的 HTTPS 证书不可用或不被信任。\n请检查系统时间、网络代理，或确认 leafreader.space 的 GitHub Pages HTTPS 证书已生效。",
                "The update feed HTTPS certificate is unavailable or not trusted.\nCheck the system clock, network proxy, or confirm GitHub Pages HTTPS is active for leafreader.space."
            )
        case .network:
            return AppText.localized(
                "无法连接 Leaf Reader 更新源。\n请检查网络、代理或 DNS；也可以在浏览器打开 leafreader.space/appcast.xml 验证是否能访问。",
                "Leaf Reader cannot reach the update feed.\nCheck network, proxy, or DNS; you can also open leafreader.space/appcast.xml in a browser."
            )
        case .appcast:
            return AppText.localized(
                "已连接更新源，但 appcast 更新信息无法读取。\n请稍后重试；如果刚发布新版本，请确认 appcast.xml 已推送并且 XML、版本号、下载链接正确。",
                "Leaf Reader reached the update feed, but the appcast could not be read.\nTry again later; if a release was just published, confirm appcast.xml, version, and download URL are correct."
            )
        case .signature:
            return AppText.localized(
                "更新包签名或 Sparkle 校验未通过。\n请不要手动安装该更新；请重新下载最新安装包，或等待发布者修复 appcast 签名、公证或安装包签名。",
                "The update package signature or Sparkle validation failed.\nDo not install this update manually; download the latest installer again or wait for the appcast signature, notarization, or package signature to be fixed."
            )
        case .other:
            break
        }

        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = nsError.localizedRecoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = nsError.localizedFailureReason?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let suggestion, !suggestion.isEmpty {
            return "\(description)\n\(suggestion)"
        }
        if let reason, !reason.isEmpty, reason != description {
            return "\(description)\n\(reason)"
        }
        if !description.isEmpty {
            return description
        }
        return AppText.localized("暂时无法检查更新，请检查网络后再试。", "Unable to check for updates. Please check your network connection and try again.")
    }

    private func showUpToDateUpdateStatus() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? appVersionText()
        showWhiteUpdateStatus(
            title: AppText.localized("已是最新版本", "You're up to date!"),
            message: AppText.localized(
                "Leaf Reader \(version) 已是当前最新版本。",
                "Leaf Reader \(version) is currently the newest version available."
            )
        )
    }

}

extension AppDelegate: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard manualUpdateProbeInProgress else { return }
        manualUpdateProbeFoundUpdate = true
        manualUpdateProbeHandledResult = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard manualUpdateProbeInProgress, !manualUpdateProbeFoundUpdate else { return }
        manualUpdateProbeHandledResult = true
        showWhiteUpdateStatus(
            title: AppText.localized("检查更新失败", "Update Check Failed"),
            message: updateFailureMessage(from: error)
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        guard manualUpdateProbeInProgress, !manualUpdateProbeFoundUpdate else { return }
        manualUpdateProbeHandledResult = true
        showUpToDateUpdateStatus()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard manualUpdateProbeInProgress else { return }

        let shouldPresentUpdate = manualUpdateProbeFoundUpdate
        let shouldShowError = !manualUpdateProbeHandledResult && error != nil
        let shouldShowUpToDate = !manualUpdateProbeHandledResult && !manualUpdateProbeFoundUpdate && error == nil

        manualUpdateProbeInProgress = false
        manualUpdateProbeFoundUpdate = false
        manualUpdateProbeHandledResult = false
        let sender = manualUpdateSender
        manualUpdateSender = nil

        if shouldPresentUpdate {
            updateStatusWindow?.close()
            showStandardUpdateWhenReady(sender: sender)
        } else if shouldShowError {
            showWhiteUpdateStatus(
                title: AppText.localized("检查更新失败", "Update Check Failed"),
                message: updateFailureMessage(from: error)
            )
        } else if shouldShowUpToDate {
            showUpToDateUpdateStatus()
        }
    }

    private func showStandardUpdateWhenReady(
        sender: AnyObject?,
        attemptsRemaining: Int = AppDelegate.updateWindowOpenRetryLimit
    ) {
        guard let updaterController else { return }
        if !updaterController.updater.sessionInProgress {
            updaterController.checkForUpdates(sender)
            return
        }

        guard attemptsRemaining > 0 else {
            showWhiteUpdateStatus(
                title: AppText.localized("发现新版本", "Update Available"),
                message: AppText.localized(
                    "更新窗口暂时无法打开，请稍后再点一次“检查更新”。",
                    "The update window is not ready yet. Please choose Check for Updates again in a moment."
                )
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.updateWindowOpenRetryDelay) { [weak self, weak sender] in
            self?.showStandardUpdateWhenReady(sender: sender, attemptsRemaining: attemptsRemaining - 1)
        }
    }
}

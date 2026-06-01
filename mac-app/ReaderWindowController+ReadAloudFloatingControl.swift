import Cocoa

extension ReaderWindowController {
    private enum FloatingControlMetrics {
        static let controlSize = NSSize(width: 462, height: 40)
        static let shortcutHintSize = NSSize(width: 360, height: 126)
        static let bottomInset: CGFloat = 14
        static let shortcutHintSpacing: CGFloat = 8
        static let shortcutHintDisplayDuration: TimeInterval = 6
        static let fadeDuration: TimeInterval = 0.16
    }

    private enum FloatingControlDefaults {
        static let hasShownShortcutHintKey = "hasShownReadAloudShortcutHint"
    }

    func installReadAloudFloatingControlIfNeeded() {
        guard readAloudFloatingControlView == nil else { return }
        let control = ReadAloudFloatingControlView()
        configureReadAloudFloatingControlActions(control)
        control.isHidden = true
        control.applyTheme(ReaderTheme.selected)
        control.frame = NSRect(origin: .zero, size: FloatingControlMetrics.controlSize)

        let controlWindow = NSWindow(
            contentRect: control.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureReadAloudFloatingControlWindow(controlWindow, contentView: control)
        readAloudFloatingControlView = control
        readAloudFloatingControlWindow = controlWindow
    }

    private func configureReadAloudFloatingControlActions(_ control: ReadAloudFloatingControlView) {
        control.previousButton.target = self
        control.previousButton.action = #selector(previousReadAloudFromFloatingControl)
        control.playPauseButton.target = self
        control.playPauseButton.action = #selector(toggleReadAloudFromFloatingControl)
        control.stopButton.target = self
        control.stopButton.action = #selector(stopReadAloudFromFloatingControl)
        control.replayButton.target = self
        control.replayButton.action = #selector(replayReadAloudFromFloatingControl)
        control.nextButton.target = self
        control.nextButton.action = #selector(advanceReadAloudFromFloatingControl)
        control.nextPageButton.target = self
        control.nextPageButton.action = #selector(advanceReadAloudToNextPageFromFloatingControl)
        control.settingsButton.target = self
        control.settingsButton.action = #selector(openReadAloudSettingsFromFloatingControl)
        control.modeButton.target = self
        control.modeButton.action = #selector(toggleReadAloudAdvanceModeFromFloatingControl)
        control.speedSlider.target = self
        control.speedSlider.action = #selector(changeReadAloudSpeedFromFloatingControl(_:))
    }

    private func configureReadAloudFloatingControlWindow(_ controlWindow: NSWindow, contentView: NSView) {
        controlWindow.contentView = contentView
        controlWindow.backgroundColor = .clear
        controlWindow.isOpaque = false
        controlWindow.hasShadow = false
        controlWindow.hidesOnDeactivate = false
        controlWindow.ignoresMouseEvents = false
        controlWindow.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        controlWindow.isReleasedWhenClosed = false
        window?.addChildWindow(controlWindow, ordered: .above)
        controlWindow.orderOut(nil)
    }

    func updateReadAloudFloatingControl() {
        installReadAloudFloatingControlIfNeeded()
        guard let control = readAloudFloatingControlView else { return }
        control.isHidden = !isReadAloudActive
        control.applyTheme(ReaderTheme.selected)
        control.update(
            isPaused: isReadAloudPaused,
            isLoading: isReadAloudLoading,
            mode: readAloudAdvanceMode,
            canGoPrevious: canReadAloudGoPrevious,
            speedID: AISettingsStore.selectedSpeechSpeedID
        )
        updateReadAloudFloatingControlWindowFrame()
        if isReadAloudActive {
            showReadAloudFloatingControlWindow()
            showReadAloudShortcutHintIfNeeded(mode: readAloudAdvanceMode)
        } else {
            readAloudFloatingControlWindow?.orderOut(nil)
            dismissReadAloudShortcutHint()
        }
        updateReadAloudSoftHintPosition()
    }

    func showReadAloudFloatingControlWindow() {
        guard isReadAloudActive,
              let parentWindow = window,
              let controlWindow = readAloudFloatingControlWindow else { return }
        updateReadAloudFloatingControlWindowFrame()
        if controlWindow.parent !== parentWindow {
            controlWindow.parent?.removeChildWindow(controlWindow)
            parentWindow.addChildWindow(controlWindow, ordered: .above)
        }
        controlWindow.level = parentWindow.level
        controlWindow.orderFront(nil)
        updateReadAloudShortcutHintWindowFrame()
    }

    func updateReadAloudFloatingControlWindowFrame() {
        guard let parentWindow = window,
              let controlWindow = readAloudFloatingControlWindow else { return }
        let size = controlWindow.frame.size
        let pointInWindow = pdfContainer.convert(
            NSPoint(
                x: pdfContainer.bounds.midX - size.width / 2,
                y: pdfContainer.bounds.minY + FloatingControlMetrics.bottomInset
            ),
            to: nil
        )
        let pointInScreen = parentWindow.convertPoint(toScreen: pointInWindow)
        controlWindow.setFrameOrigin(pointInScreen)
        updateReadAloudShortcutHintWindowFrame()
    }

    private func installReadAloudShortcutHintIfNeeded() {
        guard readAloudShortcutHintWindow == nil else { return }
        let hint = ReadAloudShortcutHintView(frame: NSRect(origin: .zero, size: FloatingControlMetrics.shortcutHintSize))
        hint.text = AppText.localized("按键功能说明", "Key Function Guide")
        hint.applyTheme(ReaderTheme.selected)
        hint.alphaValue = 0

        let hintWindow = NSWindow(
            contentRect: hint.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hintWindow.contentView = hint
        hintWindow.backgroundColor = .clear
        hintWindow.isOpaque = false
        hintWindow.hasShadow = false
        hintWindow.hidesOnDeactivate = false
        hintWindow.ignoresMouseEvents = true
        hintWindow.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        hintWindow.isReleasedWhenClosed = false

        readAloudShortcutHintView = hint
        readAloudShortcutHintWindow = hintWindow
    }

    private func showReadAloudShortcutHintIfNeeded(mode: ReadAloudAdvanceMode) {
        guard mode == .manual,
              !UserDefaults.standard.bool(forKey: FloatingControlDefaults.hasShownShortcutHintKey),
              let parentWindow = window else { return }
        installReadAloudShortcutHintIfNeeded()
        guard let hintWindow = readAloudShortcutHintWindow,
              let hintView = readAloudShortcutHintView else { return }

        UserDefaults.standard.set(true, forKey: FloatingControlDefaults.hasShownShortcutHintKey)
        hintView.applyTheme(ReaderTheme.selected)
        updateReadAloudShortcutHintWindowFrame()
        if hintWindow.parent !== parentWindow {
            hintWindow.parent?.removeChildWindow(hintWindow)
            parentWindow.addChildWindow(hintWindow, ordered: .above)
        }
        hintWindow.level = parentWindow.level
        hintWindow.orderFront(nil)

        readAloudShortcutHintDismissWorkItem?.cancel()
        hintView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingControlMetrics.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hintView.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissReadAloudShortcutHint()
        }
        readAloudShortcutHintDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + FloatingControlMetrics.shortcutHintDisplayDuration, execute: workItem)
    }

    private func updateReadAloudShortcutHintWindowFrame() {
        guard let controlWindow = readAloudFloatingControlWindow,
              let hintWindow = readAloudShortcutHintWindow else { return }
        let controlFrame = controlWindow.frame
        let hintSize = hintWindow.frame.size
        let origin = NSPoint(
            x: controlFrame.midX - hintSize.width / 2,
            y: controlFrame.maxY + FloatingControlMetrics.shortcutHintSpacing
        )
        hintWindow.setFrameOrigin(origin)
    }

    private func dismissReadAloudShortcutHint() {
        readAloudShortcutHintDismissWorkItem?.cancel()
        readAloudShortcutHintDismissWorkItem = nil
        guard let hintWindow = readAloudShortcutHintWindow,
              let hintView = readAloudShortcutHintView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = FloatingControlMetrics.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hintView.animator().alphaValue = 0
        } completionHandler: {
            hintWindow.orderOut(nil)
        }
    }

    @objc func toggleReadAloudFromFloatingControl() {
        readAloudCoordinator.toggleFromToolbar()
    }

    @objc func stopReadAloudFromFloatingControl() {
        readAloudCoordinator.stopImmediately()
    }

    @objc func replayReadAloudFromFloatingControl() {
        readAloudCoordinator.replayCurrentSegment()
    }

    @objc func advanceReadAloudFromFloatingControl() {
        readAloudCoordinator.advanceSegment()
    }

    @objc func previousReadAloudFromFloatingControl() {
        readAloudCoordinator.replayPreviousSegment()
    }

    @objc func advanceReadAloudToNextPageFromFloatingControl() {
        guard isReadAloudActive, !isReadAloudLoading else { return }
        if currentDocumentKind == .pdf {
            skipReadAloudToNextPDFPage()
        } else {
            skipReadAloudToNextWebPage()
        }
    }

    @objc func openReadAloudSettingsFromFloatingControl() {
        openSettingsPanel(tab: .speech)
    }

    @objc func toggleReadAloudAdvanceModeFromFloatingControl() {
        readAloudCoordinator.toggleAdvanceMode()
    }

    @objc func changeReadAloudSpeedFromFloatingControl(_ sender: NSSlider) {
        let speedID = AISettingsStore.speechSpeedID(forSliderValue: sender.doubleValue)
        AISettingsStore.saveSpeechSpeedID(speedID)
        readAloudFloatingControlView?.updateSpeedSlider(speedID: speedID)
    }

    func pauseReadAloudForManualAdvance() {
        readAloudCoordinator.pauseForManualAdvance()
    }
}

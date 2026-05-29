import Cocoa

extension ReaderWindowController {
    private static let readAloudFloatingControlSize = NSSize(width: 424, height: 40)
    private static let readAloudFloatingControlBottomInset: CGFloat = 14

    func installReadAloudFloatingControlIfNeeded() {
        guard readAloudFloatingControlView == nil else { return }
        let control = ReadAloudFloatingControlView()
        configureReadAloudFloatingControlActions(control)
        control.isHidden = true
        control.applyTheme(ReaderTheme.selected)
        control.frame = NSRect(origin: .zero, size: Self.readAloudFloatingControlSize)

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
        } else {
            readAloudFloatingControlWindow?.orderOut(nil)
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
    }

    func updateReadAloudFloatingControlWindowFrame() {
        guard let parentWindow = window,
              let controlWindow = readAloudFloatingControlWindow else { return }
        let size = controlWindow.frame.size
        let pointInWindow = pdfContainer.convert(
            NSPoint(
                x: pdfContainer.bounds.midX - size.width / 2,
                y: pdfContainer.bounds.minY + Self.readAloudFloatingControlBottomInset
            ),
            to: nil
        )
        let pointInScreen = parentWindow.convertPoint(toScreen: pointInWindow)
        controlWindow.setFrameOrigin(pointInScreen)
    }

    @objc func toggleReadAloudFromFloatingControl() {
        toggleReadAloudFromToolbar()
    }

    @objc func stopReadAloudFromFloatingControl() {
        stopReadAloudImmediately()
    }

    @objc func advanceReadAloudFromFloatingControl() {
        guard isReadAloudActive, !isReadAloudLoading else { return }
        isReadAloudPaused = false
        updateReadAloudButton()
        if resumePendingReadAloudFromFloatingAdvanceIfNeeded() {
            return
        }
        if !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            resumePendingReadAloudIfNeeded(trigger: .userAdvance)
            return
        }
        SpeechPlaybackCoordinator.shared.advanceToNextSegment()
    }

    private func resumePendingReadAloudFromFloatingAdvanceIfNeeded() -> Bool {
        if currentDocumentKind == .pdf, pendingReadAloudPDFContinuation != nil {
            SpeechPlaybackCoordinator.shared.stopSpeaking()
            resumePendingPDFReadAloudIfNeeded(trigger: .userAdvance)
            return true
        }
        if currentDocumentKind != .pdf, pendingReadAloudWebContinuation {
            SpeechPlaybackCoordinator.shared.stopSpeaking()
            resumePendingWebReadAloudIfNeeded(trigger: .userAdvance)
            return true
        }
        return false
    }

    @objc func previousReadAloudFromFloatingControl() {
        guard isReadAloudActive, !isReadAloudLoading, canReadAloudGoPrevious else { return }
        isReadAloudPaused = false
        updateReadAloudButton()
        SpeechPlaybackCoordinator.shared.replayPreviousSegment()
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
        readAloudAdvanceMode = readAloudAdvanceMode.toggled
        readAloudAdvanceMode.save()
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(readAloudAdvanceMode == .manual)
        if readAloudAdvanceMode == .automatic, isReadAloudPaused {
            isReadAloudPaused = false
            resumePendingReadAloudIfNeeded()
        }
        updateReadAloudButton()
        updateReadAloudFloatingControl()
    }

    @objc func changeReadAloudSpeedFromFloatingControl(_ sender: NSSlider) {
        let speedID = AISettingsStore.speechSpeedID(forSliderValue: sender.doubleValue)
        AISettingsStore.saveSpeechSpeedID(speedID)
        readAloudFloatingControlView?.updateSpeedSlider(speedID: speedID)
    }

    func pauseReadAloudForManualAdvance() {
        guard readAloudAdvanceMode == .manual else { return }
        isReadAloudPaused = true
        updateReadAloudButton()
    }
}

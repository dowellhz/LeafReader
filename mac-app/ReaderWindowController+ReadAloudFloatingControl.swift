import Cocoa

extension ReaderWindowController {
    private static let readAloudFloatingControlSize = NSSize(width: 168, height: 40)
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
        control.nextButton.target = self
        control.nextButton.action = #selector(advanceReadAloudFromFloatingControl)
        control.modeButton.target = self
        control.modeButton.action = #selector(toggleReadAloudAdvanceModeFromFloatingControl)
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
            canGoPrevious: canReadAloudGoPrevious
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

    @objc func advanceReadAloudFromFloatingControl() {
        guard isReadAloudActive, !isReadAloudLoading else { return }
        isReadAloudPaused = false
        updateReadAloudButton()
        if !SpeechPlaybackCoordinator.shared.hasActiveReadAloudWork() {
            resumePendingPDFReadAloudIfNeeded()
            resumePendingWebReadAloudIfNeeded()
            return
        }
        SpeechPlaybackCoordinator.shared.advanceToNextSegment()
    }

    @objc func previousReadAloudFromFloatingControl() {
        guard isReadAloudActive, !isReadAloudLoading, canReadAloudGoPrevious else { return }
        isReadAloudPaused = false
        updateReadAloudButton()
        SpeechPlaybackCoordinator.shared.replayPreviousSegment()
    }

    @objc func toggleReadAloudAdvanceModeFromFloatingControl() {
        readAloudAdvanceMode = readAloudAdvanceMode.toggled
        readAloudAdvanceMode.save()
        SpeechPlaybackCoordinator.shared.setManualAdvanceEnabled(readAloudAdvanceMode == .manual)
        if readAloudAdvanceMode == .automatic, isReadAloudPaused {
            isReadAloudPaused = false
            resumePendingPDFReadAloudIfNeeded()
            resumePendingWebReadAloudIfNeeded()
        }
        updateReadAloudButton()
        updateReadAloudFloatingControl()
    }

    func pauseReadAloudForManualAdvance() {
        guard readAloudAdvanceMode == .manual else { return }
        isReadAloudPaused = true
        updateReadAloudButton()
    }
}

import Cocoa

extension ReaderWindowController {
    @objc func toggleReadAloudFromToolbar() {
        readAloudCoordinator.toggleFromToolbar()
    }

    @objc func stopReadAloudFromToolbarAction() {
        readAloudCoordinator.stopImmediately()
    }

    func stopReadAloudImmediately() {
        readAloudCoordinator.stopImmediately()
    }

    func finishReadAloudFromToolbar() {
        readAloudCoordinator.finishFromToolbar()
    }

    func beginReadAloudLoading() {
        readAloudCoordinator.beginLoading()
    }

    func handleReadAloudStartResult(didUseLocalTTS: Bool) {
        readAloudCoordinator.handleStartResult(didUseLocalTTS: didUseLocalTTS)
    }

    func updateReadAloudButton() {
        guard let readAloudButton else { return }
        let symbolName = isReadAloudLoading
            ? "hourglass"
            : (isReadAloudPaused ? "play.fill" : (isReadAloudActive ? "pause.fill" : "speaker.wave.2"))
        readAloudButton.title = isReadAloudLoading
            ? AppText.localized("加载中", "Loading")
            : (isReadAloudPaused
            ? AppText.localized("继续", "Resume")
            : (isReadAloudActive ? AppText.localized("暂停", "Pause") : AppText.localized("朗读", "Read")))
        readAloudButton.isEnabled = !isReadAloudLoading
        setCapsuleButtonSymbol(symbolName, on: readAloudButton, accessibilityDescription: readAloudButton.title)
        readAloudButton.toolTip = isReadAloudLoading
            ? AppText.localized("正在加载朗读模型", "Loading read aloud model")
            : (isReadAloudPaused
            ? AppText.localized("继续朗读", "Resume reading")
            : (isReadAloudActive
                ? AppText.localized("暂停朗读", "Pause reading")
                : AppText.localized("从当前屏幕顶部开始朗读", "Read from the top of the current screen")))
        readAloudStopButton?.isHidden = !isReadAloudActive
        readAloudButton.needsDisplay = true
        readAloudButton.displayIfNeeded()
        updateReadAloudFloatingControl()
    }

    func resumePendingReadAloudIfNeeded(trigger: ReadAloudContinuationTrigger = .automatic) {
        readAloudCoordinator.resumePendingIfNeeded(trigger: trigger)
    }

    func shouldPauseBeforeReadAloudContinuation(trigger: ReadAloudContinuationTrigger) -> Bool {
        readAloudCoordinator.shouldPauseBeforeContinuation(trigger: trigger)
    }

    func deferReadAloudContinuationIfNeeded(
        trigger: ReadAloudContinuationTrigger,
        setPending: () -> Void
    ) -> Bool {
        readAloudCoordinator.deferContinuationIfNeeded(trigger: trigger, setPending: setPending)
    }

}

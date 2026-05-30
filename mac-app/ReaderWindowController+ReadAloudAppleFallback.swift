extension ReaderWindowController: VocabularySpeechCoordinatorOwner {
    var shouldResumeReadAloudAfterVocabularySpeech: Bool {
        isReadAloudActive && !isReadAloudPaused
    }

    func prepareForVocabularySpeechStart() {
        resetReadAloudPDFProgress()
        readAloudPDFPages = pdfView.currentSelection?.pages ?? []
    }

    func pauseReadAloudForVocabularySpeech() {
        guard isReadAloudActive, !isReadAloudPaused else { return }
        readAloudState.pausePlayback()
        SpeechPlaybackCoordinator.shared.pauseSpeaking()
        updateReadAloudButton()
    }

    func resumeReadAloudAfterVocabularySpeech(shouldResume: Bool) {
        guard shouldResume, isReadAloudActive, isReadAloudPaused else { return }
        readAloudState.resumePlayback()
        SpeechPlaybackCoordinator.shared.resumeSpeaking()
        updateReadAloudButton()
    }

    func clearReaderSelectionForVocabularySpeech() {
        clearReaderSelectionForBubbleSelection()
    }
}

import Cocoa

final class VocabularySpeakerButton: NSButton {
    var spokenWord: String?

    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class VocabularyDetailScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return }
        super.scrollWheel(with: event)
    }
}

final class VocabularyDetailClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }
}

extension ReaderWindowController {
    var vocabularyReviewButtonWidth: CGFloat { 108 }
    var vocabularyReviewButtonHeight: CGFloat { 36 }
    var vocabularyReviewButtonFontSize: CGFloat { 14 }

    func vocabularyPanelBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func vocabularyPrimaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return NSColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1)
        }
    }

    func vocabularySecondaryTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.48, green: 0.54, blue: 0.66, alpha: 1)
        case .eyeCare:
            return theme.secondaryTextColor
        case .dark:
            return NSColor(red: 0.60, green: 0.67, blue: 0.76, alpha: 1)
        }
    }

    func vocabularyBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    func vocabularyCardBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.985, green: 0.988, blue: 0.995, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.88, green: 0.83, blue: 0.68, alpha: 1)
        case .dark:
            return NSColor(red: 0.13, green: 0.16, blue: 0.20, alpha: 1)
        }
    }

    func vocabularyCardBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.68, green: 0.61, blue: 0.43, alpha: 1)
        case .dark:
            return NSColor(red: 0.25, green: 0.30, blue: 0.36, alpha: 1)
        }
    }

    func vocabularyBodyTextColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.22, green: 0.25, blue: 0.31, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.25, green: 0.20, blue: 0.12, alpha: 1)
        case .dark:
            return NSColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1)
        }
    }

    func vocabularyButtonBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.92, green: 0.87, blue: 0.72, alpha: 1)
        case .dark:
            return NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    func vocabularyPrimaryActionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.accentColor
    }

    func vocabularyPrimaryActionTextColor(for theme: ReaderTheme) -> NSColor {
        theme.primaryActionTextColor
    }

    func vocabularyAccentColor(for theme: ReaderTheme) -> NSColor {
        theme.strongAccentColor
    }

    func vocabularySelectionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        vocabularyAccentColor(for: theme).withAlphaComponent(theme == .eyeCare ? 0.24 : 0.20)
    }

    func styleVocabularyActionButton(_ button: ThemedSettingsActionButton, fontSize: CGFloat = 14, isPrimary: Bool = false) {
        let theme = ReaderTheme.selected
        button.fillColor = isPrimary ? vocabularyPrimaryActionBackgroundColor(for: theme) : vocabularyButtonBackgroundColor(for: theme)
        button.strokeColor = isPrimary ? vocabularyPrimaryActionBackgroundColor(for: theme) : vocabularyBorderColor(for: theme)
        button.labelColor = isPrimary ? vocabularyPrimaryActionTextColor(for: theme) : vocabularyPrimaryTextColor(for: theme)
        button.font = AppFont.semibold(ofSize: fontSize)
        button.lineBreakMode = .byTruncatingTail
    }

    func vocabularyActionButton(title: String, target: AnyObject?, action: Selector?, fontSize: CGFloat = 14, isPrimary: Bool = false) -> ThemedSettingsActionButton {
        let button = ThemedSettingsActionButton(title: title, target: target, action: action)
        button.controlSize = .large
        styleVocabularyActionButton(button, fontSize: fontSize, isPrimary: isPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc func showVocabularyBook() {
        let aggregatedRecords = VocabularyRecordProvider.records(
            documentKind: currentDocumentKind,
            pdfRecords: storedWordRecords,
            webRecords: storedWebWordRecords,
            pdfContext: { [weak self] in
                VocabularyContextProvider.pdfContext(for: $0, document: self?.pdfView.document)
            }
        )
        guard !aggregatedRecords.isEmpty else {
            NSSound.beep()
            return
        }
        currentVocabularyExportRecords = aggregatedRecords
        vocabularyReviewSession.filter = .due
        vocabularyReviewSession.resetForReviewMode()
        vocabularyPanelController.show(records: aggregatedRecords)
    }
}

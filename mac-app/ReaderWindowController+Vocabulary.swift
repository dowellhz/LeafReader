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
        theme.vocabularyPanelBackgroundColor
    }

    func vocabularyPrimaryTextColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyPrimaryTextColor
    }

    func vocabularySecondaryTextColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularySecondaryTextColor
    }

    func vocabularyBorderColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyBorderColor
    }

    func vocabularyCardBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyCardBackgroundColor
    }

    func vocabularyCardBorderColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyCardBorderColor
    }

    func vocabularyBodyTextColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyBodyTextColor
    }

    func vocabularyButtonBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyButtonBackgroundColor
    }

    func vocabularyPrimaryActionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.accentColor
    }

    func vocabularyPrimaryActionTextColor(for theme: ReaderTheme) -> NSColor {
        theme.primaryActionTextColor
    }

    func vocabularyAccentColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularyAccentColor
    }

    func vocabularySelectionBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.vocabularySelectionBackgroundColor
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
}

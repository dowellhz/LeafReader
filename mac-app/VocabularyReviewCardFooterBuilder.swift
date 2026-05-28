import Cocoa

final class VocabularyReviewCardFooterBuilder {
    private unowned let owner: ReaderWindowController

    init(owner: ReaderWindowController) {
        self.owner = owner
    }

    func addAnswerFooter(to footerArea: NSView, didScore: Bool, canUndoScore: Bool) {
        let nextButton = reviewActionButton(title: AppText.localized("下一个", "Next"), action: #selector(ReaderWindowController.nextVocabularyReviewCard(_:)), isPrimary: true)
        let footerButtons: NSView
        if didScore, canUndoScore {
            let undoButton = reviewActionButton(title: AppText.localized("撤销", "Undo"), action: #selector(ReaderWindowController.undoVocabularyReviewScore(_:)))
            footerButtons = reviewButtonRow([undoButton, nextButton])
        } else {
            footerButtons = nextButton
        }
        addFooterButtons(footerButtons, to: footerArea)
    }

    func addContextFooter(to footerArea: NSView) {
        let rememberedButton = reviewActionButton(title: AppText.localized("想起来了", "Remembered"), action: #selector(ReaderWindowController.rememberedAfterContextVocabularyCard(_:)), isPrimary: true)
        let forgotButton = reviewActionButton(title: AppText.localized("没想起来", "Forgot"), action: #selector(ReaderWindowController.showVocabularyAnswer(_:)))
        addFooterButtons(reviewButtonRow([rememberedButton, forgotButton]), to: footerArea)
    }

    func addPromptFooter(to footerArea: NSView) {
        let rememberedButton = reviewActionButton(title: AppText.localized("认识", "Know"), action: #selector(ReaderWindowController.rememberedVocabularyCard(_:)), isPrimary: true)
        let forgotButton = reviewActionButton(title: AppText.localized("不认识", "Do not know"), action: #selector(ReaderWindowController.showVocabularyContext(_:)))
        addFooterButtons(reviewButtonRow([rememberedButton, forgotButton]), to: footerArea)
    }

    private func addFooterButtons(_ buttons: NSView, to footerArea: NSView) {
        footerArea.addSubview(buttons)
        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: footerArea.trailingAnchor),
            buttons.centerYAnchor.constraint(equalTo: footerArea.centerYAnchor)
        ])
    }

    private func reviewActionButton(title: String, action: Selector, isPrimary: Bool = false) -> NSButton {
        let button = owner.vocabularyActionButton(
            title: title,
            target: owner,
            action: action,
            fontSize: owner.vocabularyReviewButtonFontSize,
            isPrimary: isPrimary
        )
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: owner.vocabularyReviewButtonWidth),
            button.heightAnchor.constraint(equalToConstant: owner.vocabularyReviewButtonHeight)
        ])
        return button
    }

    private func reviewButtonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}

import Cocoa

struct ReaderToolbarSetup {
    let toolbar: NSView
    let zoomOut: NSButton
    let zoomIn: NSButton
    let leftDivider: NSView
    let rightDivider: NSView
    let zoomGroup: NSView
}

struct ReaderBottomBarSetup {
    let bottomBar: NSView
    let settingsButton: NSButton
    let navigationStack: NSStackView
}

enum ReaderUILayout {
    static let toolbarHeight: CGFloat = 58
    static let bottomBarHeight: CGFloat = 52
    static let collapsedAIPanelWidth: CGFloat = 1
    static let resizeHandleWidth: CGFloat = 6
    static let aiHandleTopOffset: CGFloat = 90

    static let settingsLeading: CGFloat = 18
    static let settingsButtonSize: CGFloat = 24
    static let shelfButtonLeading: CGFloat = 18
    static let shelfButtonWidth: CGFloat = 88
    static let vocabularyButtonLeading: CGFloat = 10
    static let vocabularyButtonWidth: CGFloat = 92
    static let bottomButtonHeight: CGFloat = 30

    static let coverLeading: CGFloat = 128
    static let coverSize = CGSize(width: 28, height: 38)
    static let titleLeading: CGFloat = 10
    static let titleMaxWidth: CGFloat = 230
    static let titleToReadAloudMinimum: CGFloat = 14
    static let readAloudButtonWidth: CGFloat = 82
    static let readAloudStopLeading: CGFloat = 6
    static let readAloudStopButtonWidth: CGFloat = 82
    static let readAloudTrailingToZoom: CGFloat = 14

    static let zoomCenterOffset: CGFloat = -80
    static let zoomGroupSize = CGSize(width: 132, height: 32)
    static let zoomButtonWidth: CGFloat = 40
    static let zoomDividerWidth: CGFloat = 1
    static let zoomFieldWidth: CGFloat = 50

    static let pageLabelCenterOffset: CGFloat = 130
    static let pageLabelWidth: CGFloat = 170
    static let searchUnderlineLeading: CGFloat = 6
    static let searchUnderlineSize = CGSize(width: 74, height: 28)
    static let searchButtonLeading: CGFloat = 2
    static let iconButtonSize: CGFloat = 28

    static let pageLayoutTrailing: CGFloat = -8
    static let pageLayoutButtonWidth: CGFloat = 84
    static let cropButtonTrailing: CGFloat = -8
    static let cropButtonWidth: CGFloat = 84
    static let fullScreenTrailing: CGFloat = -14
    static let fullScreenButtonWidth: CGFloat = 76
    static let toolbarButtonHeight: CGFloat = 30

    static let searchOverlayTop: CGFloat = 10
    static let searchOverlaySize = CGSize(width: 560, height: 70)
    static let loadingIndicatorYOffset: CGFloat = -16
    static let loadingLabelTop: CGFloat = 14
    static let loadingLabelHorizontalInset: CGFloat = 32

    static let tocButtonWidth: CGFloat = 88
    static let farthestPositionButtonWidth: CGFloat = 112
    static let coverButtonWidth: CGFloat = 100
    static let readerNavButtonWidth: CGFloat = 84
    static let navigationStackSpacing: CGFloat = 20

    static let embeddingTrailing: CGFloat = -18
    static let embeddingButtonWidth: CGFloat = 58
    static let embeddingButtonHeight: CGFloat = 26
    static let embeddingButtonSpacing: CGFloat = -8
    static let embeddingStatusTrailing: CGFloat = -10
    static let embeddingStatusLeadingMinimum: CGFloat = 16
    static let embeddingStatusMaxWidth: CGFloat = 220
}

extension ReaderWindowController {
    func installReaderLayoutConstraints(
        contentView: NSView,
        toolbarSetup: ReaderToolbarSetup,
        bottomBarSetup: ReaderBottomBarSetup
    ) {
        let toolbar = toolbarSetup.toolbar
        let zoomOut = toolbarSetup.zoomOut
        let zoomIn = toolbarSetup.zoomIn
        let zoomGroup = toolbarSetup.zoomGroup
        let leftDivider = toolbarSetup.leftDivider
        let rightDivider = toolbarSetup.rightDivider
        let bottomBar = bottomBarSetup.bottomBar
        let settingsButton = bottomBarSetup.settingsButton
        let navigationStack = bottomBarSetup.navigationStack

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarHeight),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomBarHeight),

            contentArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            pdfContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            pdfContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            pdfContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            pdfContainer.trailingAnchor.constraint(equalTo: aiPanel.leadingAnchor),

            pdfView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            pdfDimOverlay.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfDimOverlay.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfDimOverlay.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfDimOverlay.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            webView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            aiPanel.topAnchor.constraint(equalTo: contentArea.topAnchor),
            aiPanel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            aiPanel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            resizeHandle.topAnchor.constraint(equalTo: contentArea.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            resizeHandle.centerXAnchor.constraint(equalTo: aiPanel.leadingAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: ReaderUILayout.resizeHandleWidth),

            aiHandleButton.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: ReaderUILayout.aiHandleTopOffset),
            aiHandleLeadingConstraint,
            aiHandleButton.widthAnchor.constraint(equalToConstant: SideHandleButton.handleWidth),
            aiHandleButton.heightAnchor.constraint(equalToConstant: SideHandleButton.handleHeight),

            settingsButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: ReaderUILayout.settingsLeading),
            settingsButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.settingsButtonSize),
            settingsButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.settingsButtonSize),

            recentButton.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: ReaderUILayout.shelfButtonLeading),
            recentButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            recentButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.shelfButtonWidth),
            recentButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            vocabularyButton.leadingAnchor.constraint(equalTo: recentButton.trailingAnchor, constant: ReaderUILayout.vocabularyButtonLeading),
            vocabularyButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            vocabularyButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.vocabularyButtonWidth),
            vocabularyButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            coverImageView.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: ReaderUILayout.coverLeading),
            coverImageView.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: ReaderUILayout.coverSize.width),
            coverImageView.heightAnchor.constraint(equalToConstant: ReaderUILayout.coverSize.height),

            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: ReaderUILayout.titleLeading),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: ReaderUILayout.titleMaxWidth),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: readAloudButton.leadingAnchor, constant: -ReaderUILayout.titleToReadAloudMinimum),

            readAloudButton.trailingAnchor.constraint(equalTo: readAloudStopButton.leadingAnchor, constant: -ReaderUILayout.readAloudStopLeading),
            readAloudButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            readAloudButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.readAloudButtonWidth),
            readAloudButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            readAloudStopButton.trailingAnchor.constraint(equalTo: zoomGroup.leadingAnchor, constant: -ReaderUILayout.readAloudTrailingToZoom),
            readAloudStopButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            readAloudStopButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.readAloudStopButtonWidth),
            readAloudStopButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            zoomGroup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomGroup.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: ReaderUILayout.zoomCenterOffset),
            zoomGroup.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.width),
            zoomGroup.heightAnchor.constraint(equalToConstant: ReaderUILayout.zoomGroupSize.height),

            zoomOut.leadingAnchor.constraint(equalTo: zoomGroup.leadingAnchor),
            zoomOut.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomOut.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomOut.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomButtonWidth),
            leftDivider.leadingAnchor.constraint(equalTo: zoomOut.trailingAnchor),
            leftDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            leftDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            leftDivider.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomDividerWidth),
            zoomField.leadingAnchor.constraint(equalTo: leftDivider.trailingAnchor),
            zoomField.centerYAnchor.constraint(equalTo: zoomGroup.centerYAnchor),
            zoomField.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomFieldWidth),
            rightDivider.leadingAnchor.constraint(equalTo: zoomField.trailingAnchor),
            rightDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            rightDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: ReaderUILayout.zoomDividerWidth),
            zoomIn.leadingAnchor.constraint(equalTo: rightDivider.trailingAnchor),
            zoomIn.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomIn.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: zoomGroup.trailingAnchor),

            pageLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: ReaderUILayout.pageLabelCenterOffset),
            pageLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: ReaderUILayout.pageLabelWidth),

            searchUnderlineButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: ReaderUILayout.searchUnderlineLeading),
            searchUnderlineButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchUnderlineButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.searchUnderlineSize.width),
            searchUnderlineButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.searchUnderlineSize.height),

            searchButton.leadingAnchor.constraint(equalTo: searchUnderlineButton.trailingAnchor, constant: ReaderUILayout.searchButtonLeading),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.iconButtonSize),
            searchButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.iconButtonSize),

            pageLayoutButton.trailingAnchor.constraint(equalTo: cropButton.leadingAnchor, constant: ReaderUILayout.pageLayoutTrailing),
            pageLayoutButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLayoutButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.pageLayoutButtonWidth),
            pageLayoutButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            cropButton.trailingAnchor.constraint(equalTo: fullScreenButton.leadingAnchor, constant: ReaderUILayout.cropButtonTrailing),
            cropButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            cropButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.cropButtonWidth),
            cropButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            fullScreenButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: ReaderUILayout.fullScreenTrailing),
            fullScreenButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fullScreenButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.fullScreenButtonWidth),
            fullScreenButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.toolbarButtonHeight),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: ReaderUILayout.searchOverlayTop),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: ReaderUILayout.searchOverlaySize.width),
            searchOverlay.heightAnchor.constraint(equalToConstant: ReaderUILayout.searchOverlaySize.height),

            loadingOverlay.topAnchor.constraint(equalTo: contentArea.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor, constant: ReaderUILayout.loadingIndicatorYOffset),
            loadingLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: ReaderUILayout.loadingLabelTop),
            loadingLabel.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingLabel.leadingAnchor.constraint(greaterThanOrEqualTo: loadingOverlay.leadingAnchor, constant: ReaderUILayout.loadingLabelHorizontalInset),
            loadingLabel.trailingAnchor.constraint(lessThanOrEqualTo: loadingOverlay.trailingAnchor, constant: -ReaderUILayout.loadingLabelHorizontalInset),

            navigationStack.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            navigationStack.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            navigationStack.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            tocButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.tocButtonWidth),
            tocButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            coverButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.coverButtonWidth),
            coverButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            prevButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.readerNavButtonWidth),
            prevButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            nextButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.readerNavButtonWidth),
            nextButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            farthestPositionButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.farthestPositionButtonWidth),
            farthestPositionButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.bottomButtonHeight),

            embeddingCancelButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: ReaderUILayout.embeddingTrailing),
            embeddingCancelButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingCancelButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonWidth),
            embeddingCancelButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonHeight),
            embeddingPauseButton.trailingAnchor.constraint(equalTo: embeddingCancelButton.leadingAnchor, constant: ReaderUILayout.embeddingButtonSpacing),
            embeddingPauseButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingPauseButton.widthAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonWidth),
            embeddingPauseButton.heightAnchor.constraint(equalToConstant: ReaderUILayout.embeddingButtonHeight),
            embeddingStatusLabel.trailingAnchor.constraint(equalTo: embeddingPauseButton.leadingAnchor, constant: ReaderUILayout.embeddingStatusTrailing),
            embeddingStatusLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            embeddingStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: navigationStack.trailingAnchor, constant: ReaderUILayout.embeddingStatusLeadingMinimum),
            embeddingStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: ReaderUILayout.embeddingStatusMaxWidth)
        ])
    }
}

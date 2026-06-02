import Cocoa

final class ReadingNoteRowView: NSView {
    enum Metrics {
        static let height: CGFloat = 74
        static let iconSize: CGFloat = 42
        static let iconSymbolSize: CGFloat = 18
        static let pageWidth: CGFloat = 56
        static let favoriteWidth: CGFloat = 34
        static let deleteWidth: CGFloat = 48
        static let horizontalInset: CGFloat = 16
        static let columnSpacing: CGFloat = 14
    }

    var onOpen: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var onDelete: (() -> Void)?

    init(rowViewModel: ReadingNoteListRowViewModel, theme: ReaderTheme) {
        super.init(frame: .zero)
        build(rowViewModel: rowViewModel, theme: theme)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(rowViewModel: ReadingNoteListRowViewModel, theme: ReaderTheme) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = ReadingNoteTheme.cardBackground(theme).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Metrics.height).isActive = true

        let iconContainer = rowIconContainer(theme: theme)
        let icon = rowIcon(theme: theme)
        iconContainer.addSubview(icon)

        let locationLabel = NSTextField(labelWithString: rowViewModel.locationText)
        locationLabel.font = AppFont.semibold(ofSize: 15)
        locationLabel.textColor = ReadingNoteTheme.primaryText(theme)
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        let quoteLabel = NSTextField(labelWithString: rowViewModel.titleText)
        quoteLabel.font = NSFont.systemFont(ofSize: 14)
        quoteLabel.textColor = ReadingNoteTheme.primaryText(theme)
        quoteLabel.lineBreakMode = .byTruncatingTail
        quoteLabel.maximumNumberOfLines = 2
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        quoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        quoteLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let openButton = iconButton(action: #selector(openTapped(_:)))
        let favoriteButton = favoriteButton(rowViewModel: rowViewModel, theme: theme)
        let deleteButton = deleteButton(theme: theme)

        for view in [iconContainer, locationLabel, quoteLabel, openButton, favoriteButton, deleteButton] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            locationLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: Metrics.columnSpacing),
            locationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            locationLabel.widthAnchor.constraint(equalToConstant: Metrics.pageWidth),
            quoteLabel.leadingAnchor.constraint(equalTo: locationLabel.trailingAnchor, constant: Metrics.columnSpacing),
            quoteLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -Metrics.columnSpacing),
            quoteLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.topAnchor.constraint(equalTo: topAnchor),
            openButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            openButton.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -8),
            openButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            favoriteButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -2),
            favoriteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: Metrics.favoriteWidth),
            favoriteButton.heightAnchor.constraint(equalToConstant: 32),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: Metrics.deleteWidth),
            deleteButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func rowIconContainer(theme: ReaderTheme) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = ReadingNoteTheme.insetBackground(theme).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func rowIcon(theme: ReaderTheme) -> NSImageView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Metrics.iconSymbolSize, weight: .semibold))
        icon.contentTintColor = ReadingNoteTheme.accent(theme)
        icon.translatesAutoresizingMaskIntoConstraints = false
        return icon
    }

    private func iconButton(action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func favoriteButton(rowViewModel: ReadingNoteListRowViewModel, theme: ReaderTheme) -> NSButton {
        let button = iconButton(action: #selector(favoriteTapped(_:)))
        button.image = NSImage(
            systemSymbolName: rowViewModel.isFavorite ? "star.fill" : "star",
            accessibilityDescription: AppText.localized("收藏", "Favorite")
        )
        button.contentTintColor = rowViewModel.isFavorite ? ReadingNoteTheme.accent(theme) : ReadingNoteTheme.secondaryText(theme)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = rowViewModel.isFavorite
            ? AppText.localized("取消收藏", "Remove favorite")
            : AppText.localized("收藏并置顶", "Favorite and pin")
        return button
    }

    private func deleteButton(theme: ReaderTheme) -> NSButton {
        let button = NSButton(title: AppText.localized("删除", "Delete"), target: self, action: #selector(deleteTapped(_:)))
        button.isBordered = false
        button.font = AppFont.semibold(ofSize: 13)
        button.contentTintColor = ReadingNoteTheme.secondaryText(theme)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func openTapped(_ sender: NSButton) {
        onOpen?()
    }

    @objc private func favoriteTapped(_ sender: NSButton) {
        onToggleFavorite?()
    }

    @objc private func deleteTapped(_ sender: NSButton) {
        onDelete?()
    }
}

import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers

final class RecentDocumentsPanelController: NSObject {
    struct ShelfRemovalOptions {
        let clearVectorCache: Bool
        let clearWordRecords: Bool
        let clearAIData: Bool
    }

    weak var parentWindow: NSWindow?
    var panel: NSWindow?
    var onOpen: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onRemoveItem: ((String, ShelfRemovalOptions) -> Void)?
    var onClearVectorCache: ((String) -> Void)?
    var onClearWordRecords: ((String) -> Void)?
    var onClearAIData: ((String) -> Void)?
    var onImport: (([URL]) -> Void)?
    var onClose: (() -> Void)?
    var pendingOpenPath: String?
    var isClosing = false
    var appActivationObserver: NSObjectProtocol?

    let panelSize = NSSize(width: 940, height: 480)
    let coverSize = NSSize(width: 120, height: 205)
    static var coverCache: [String: NSImage] = [:]
    static var placeholderCoverCache: [String: NSImage] = [:]

    deinit {
        removeAppActivationObserver()
    }

    func show(
        items: [RecentDocumentItem],
        attachedTo window: NSWindow?,
        focusPath: String? = nil,
        onOpen: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onRemoveItem: @escaping (String, ShelfRemovalOptions) -> Void,
        onClearVectorCache: @escaping (String) -> Void,
        onClearWordRecords: @escaping (String) -> Void,
        onClearAIData: @escaping (String) -> Void,
        onImport: @escaping ([URL]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onOpen = onOpen
        self.onClear = onClear
        self.onRemoveItem = onRemoveItem
        self.onClearVectorCache = onClearVectorCache
        self.onClearWordRecords = onClearWordRecords
        self.onClearAIData = onClearAIData
        self.onImport = onImport
        self.onClose = onClose
        self.parentWindow = window

        let panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let isDark = ReaderTheme.selected == .dark
        let panelBackground = isDark
            ? NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            : NSColor.white
        let primaryText = isDark
            ? NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            : NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        let secondaryText = isDark
            ? NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
            : NSColor(red: 0.45, green: 0.49, blue: 0.60, alpha: 1)

        panel.backgroundColor = .clear
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        let content = RecentDocumentsDropContentView()
        content.onDroppedDocumentURLs = { [weak self] urls in
            self?.handleDroppedDocumentURLs(urls)
        }
        content.wantsLayer = true
        content.layer?.backgroundColor = panelBackground.cgColor
        content.layer?.borderWidth = 1
        content.layer?.borderColor = (isDark
            ? NSColor(red: 0.28, green: 0.34, blue: 0.42, alpha: 1)
            : NSColor(red: 0.84, green: 0.87, blue: 0.92, alpha: 1)
        ).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        content.layer?.shadowRadius = 32
        content.layer?.shadowOffset = CGSize(width: 0, height: -12)
        content.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = content

        let title = NSTextField(labelWithString: AppText.localized("书架", "Shelf"))
        title.font = AppFont.semibold(ofSize: 22)
        title.textColor = primaryText
        title.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "", target: self, action: #selector(closePanel(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = primaryText
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let openButton = shelfActionButton(
            title: AppText.localized("增加", "Add"),
            target: self,
            action: #selector(openDocumentFromShelf(_:)),
            panelBackground: panelBackground,
            primaryText: primaryText,
            isDark: isDark
        )
        let clearButton = shelfActionButton(
            title: AppText.localized("清空", "Clear"),
            target: self,
            action: #selector(clearRecentDocuments(_:)),
            panelBackground: panelBackground,
            primaryText: primaryText,
            isDark: isDark
        )

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 28
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        for item in items {
            let card = recentBookCard(for: item, primaryText: primaryText, secondaryText: secondaryText, isDark: isDark)
            card.onOpen = { [weak self] path in
                self?.pendingOpenPath = path
                self?.close()
            }
            card.onReveal = { path in
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            card.onRemove = { [weak self] path in
                guard let options = self?.confirmShelfRemoval() else { return }
                self?.onRemoveItem?(path, options)
                if let card = stack.arrangedSubviews.first(where: { ($0 as? RecentBookCardView)?.path == path }) {
                    stack.removeArrangedSubview(card)
                    card.removeFromSuperview()
                }
            }
            card.onClearVectorCache = { [weak self] path in
                guard self?.confirmShelfAction(
                    title: AppText.localized("清除本书 AI 阅读记录？", "Clear AI Reading Records for This Book?"),
                    message: AppText.localized("清除后，之后使用文档问答时会重新分析这本书。", "After clearing, this book will be analyzed again when document Q&A is used."),
                    confirmTitle: AppText.localized("清除", "Clear")
                ) == true else { return }
                self?.onClearVectorCache?(path)
            }
            card.onClearWordRecords = { [weak self] path in
                guard self?.confirmShelfAction(
                    title: AppText.localized("清除本书单词记录？", "Clear Word Records for This Book?"),
                    message: AppText.localized("这会删除本书已保存的单词、解释和高亮记录。", "This deletes saved words, explanations, and highlights for this book."),
                    confirmTitle: AppText.localized("清除", "Clear")
                ) == true else { return }
                self?.onClearWordRecords?(path)
            }
            card.onClearAIData = { [weak self] path in
                guard self?.confirmShelfAction(
                    title: AppText.localized("清除本书 AI 数据？", "Clear AI Data for This Book?"),
                    message: AppText.localized("这会删除本书已保存的 AI 对话、来源标注和单词学习记录。", "This deletes saved AI conversations, source marks, and word learning records for this book."),
                    confirmTitle: AppText.localized("清除", "Clear")
                ) == true else { return }
                self?.onClearAIData?(path)
            }
            stack.addArrangedSubview(card)
        }

        for view in [title, closeButton, openButton, clearButton, scrollView] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),

            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            clearButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -22),
            clearButton.widthAnchor.constraint(equalToConstant: 68),
            clearButton.heightAnchor.constraint(equalToConstant: 28),
            openButton.centerYAnchor.constraint(equalTo: clearButton.centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -10),
            openButton.widthAnchor.constraint(equalToConstant: 68),
            openButton.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 38),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -42),

            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor)
        ])

        self.panel = panel
        installAppActivationObserver()
        showPanel(panel, attachedTo: window)
        if let focusPath {
            DispatchQueue.main.async {
                guard let card = stack.arrangedSubviews
                    .compactMap({ $0 as? RecentBookCardView })
                    .first(where: { $0.path == focusPath }) else { return }
                card.scrollToVisible(card.bounds)
            }
        }
    }
}

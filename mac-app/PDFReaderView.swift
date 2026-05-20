import Cocoa
import PDFKit

final class EdgePagingPDFView: PDFView {
    enum ScrollPageDirection: Equatable {
        case previous
        case next
    }

    var onScrollPastPageEdge: ((ScrollPageDirection) -> Void)?
    var onDroppedDocumentURLs: (([URL]) -> Void)?

    private var accumulatedEdgeScroll: CGFloat = 0
    private var lastEdgePageTurn = Date.distantPast

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        ReaderFileDrop.register(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        ReaderFileDrop.register(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ReaderFileDrop.operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ReaderFileDrop.perform(sender) { [weak self] urls in
            self?.onDroppedDocumentURLs?(urls)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let sourceMenu = super.menu(for: event) ?? fallbackContextMenu()
        return sanitizedContextMenu(from: sourceMenu)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let selection = copiedCurrentSelection(),
              (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            super.rightMouseDown(with: event)
            return
        }

        setCurrentSelection(selection, animate: false)
        guard let menu = menu(for: event) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        if currentSelection?.string?.isEmpty != false {
            setCurrentSelection(selection, animate: false)
        }
    }

    private func copiedCurrentSelection() -> PDFSelection? {
        currentSelection?.copy() as? PDFSelection
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began {
            accumulatedEdgeScroll = 0
        }

        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(event.scrollingDeltaX), abs(deltaY) > 0 else {
            accumulatedEdgeScroll = 0
            super.scrollWheel(with: event)
            return
        }

        if event.hasPreciseScrollingDeltas {
            super.scrollWheel(with: event)
            return
        }

        super.scrollWheel(with: event)

        let direction: ScrollPageDirection?
        if deltaY > 0, isScrolledToTop {
            direction = .previous
        } else if deltaY < 0, isScrolledToBottom {
            direction = .next
        } else {
            accumulatedEdgeScroll = 0
            direction = nil
        }

        guard let direction else { return }
        accumulatedEdgeScroll += abs(deltaY)
        guard accumulatedEdgeScroll >= PDFPagingPolicy.wheelEdgeScrollThreshold else { return }

        accumulatedEdgeScroll = 0
        turnPage(direction)
    }

    private func turnPage(_ direction: ScrollPageDirection) {
        let now = Date()
        guard now.timeIntervalSince(lastEdgePageTurn) > PDFPagingPolicy.wheelPageTurnCooldown else { return }
        lastEdgePageTurn = now
        onScrollPastPageEdge?(direction)
    }

    private var isScrolledToTop: Bool {
        guard let scrollView = pdfScrollView else { return false }
        return scrollView.contentView.bounds.minY <= 2
    }

    private var isScrolledToBottom: Bool {
        guard let scrollView = pdfScrollView else { return false }
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return true }
        let clipHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        guard documentHeight > clipHeight + PDFPagingPolicy.documentSizeTolerance else { return true }
        return clipView.bounds.maxY >= documentHeight - PDFPagingPolicy.documentSizeTolerance
    }

    private var pdfScrollView: NSScrollView? {
        if let scrollView = enclosingScrollView {
            return scrollView
        }
        return firstScrollView(in: self)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func fallbackContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        return menu
    }

    private func sanitizedContextMenu(from sourceMenu: NSMenu) -> NSMenu {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false

        let groups = [
            resizeContextMenuTitles,
            pageLayoutContextMenuTitles,
            pageTurnContextMenuTitles
        ]
        for allowedGroup in groups {
            var didAddGroupItem = false
            for item in sourceMenu.items {
                guard !item.isSeparatorItem,
                      allowedGroup.contains(normalizedContextMenuTitle(item.title)) else {
                    continue
                }
                let copy = NSMenuItem(title: localizedAllowedContextMenuTitle(item.title), action: item.action, keyEquivalent: "")
                copy.target = item.target
                copy.state = item.state
                copy.isEnabled = item.isEnabled
                copy.tag = item.tag
                copy.representedObject = item.representedObject
                copy.image = item.image
                menu.addItem(copy)
                didAddGroupItem = true
            }
            if didAddGroupItem {
                menu.addItem(.separator())
            }
        }
        trimContextMenuSeparators(menu)
        return menu
    }

    private func normalizedContextMenuTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "...")
            .lowercased()
    }

    private var resizeContextMenuTitles: Set<String> {
        Set([
            "automatically resize", "自动调整大小",
            "zoom in", "放大",
            "zoom out", "缩小",
            "actual size", "实际大小"
        ])
    }

    private var pageLayoutContextMenuTitles: Set<String> {
        Set([
            "single page", "单页",
            "single page continuous", "单页连续",
            "two pages", "双页",
            "two pages continuous", "双页连续"
        ])
    }

    private var pageTurnContextMenuTitles: Set<String> {
        Set([
            "next page", "下一页",
            "previous page", "上一页"
        ])
    }

    private func trimContextMenuSeparators(_ menu: NSMenu) {
        while menu.items.first?.isSeparatorItem == true {
            menu.removeItem(at: 0)
        }
        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }
        var index = menu.items.count - 1
        while index > 0 {
            if menu.items[index].isSeparatorItem, menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            }
            index -= 1
        }
    }

    private func localizedAllowedContextMenuTitle(_ title: String) -> String {
        switch normalizedContextMenuTitle(title) {
        case "automatically resize", "自动调整大小":
            return localizedMenuTitle(zh: "自动调整大小", en: "Automatically Resize")
        case "zoom in", "放大":
            return localizedMenuTitle(zh: "放大", en: "Zoom In")
        case "zoom out", "缩小":
            return localizedMenuTitle(zh: "缩小", en: "Zoom Out")
        case "actual size", "实际大小":
            return localizedMenuTitle(zh: "实际大小", en: "Actual Size")
        case "single page", "单页":
            return localizedMenuTitle(zh: "单页", en: "Single Page")
        case "single page continuous", "单页连续":
            return localizedMenuTitle(zh: "单页连续", en: "Single Page Continuous")
        case "two pages", "双页":
            return localizedMenuTitle(zh: "双页", en: "Two Pages")
        case "two pages continuous", "双页连续":
            return localizedMenuTitle(zh: "双页连续", en: "Two Pages Continuous")
        case "next page", "下一页":
            return localizedMenuTitle(zh: "下一页", en: "Next Page")
        case "previous page", "上一页":
            return localizedMenuTitle(zh: "上一页", en: "Previous Page")
        default:
            return title
        }
    }

    private func localizedContextMenuTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return title }

        if trimmed.hasPrefix("Look Up ") {
            let query = String(trimmed.dropFirst("Look Up ".count))
            return localizedMenuTitle(zh: "查询 \(query)", en: "Look Up \(query)")
        }
        if trimmed.hasPrefix("Search with ") {
            let engine = String(trimmed.dropFirst("Search with ".count))
            return localizedMenuTitle(zh: "用 \(engine) 搜索", en: "Search with \(engine)")
        }
        if trimmed.hasPrefix("查询 ") {
            let query = String(trimmed.dropFirst("查询 ".count))
            return localizedMenuTitle(zh: "查询 \(query)", en: "Look Up \(query)")
        }
        if trimmed.hasPrefix("用 "), trimmed.hasSuffix(" 搜索") {
            let engine = String(trimmed.dropFirst("用 ".count).dropLast(" 搜索".count))
            return localizedMenuTitle(zh: "用 \(engine) 搜索", en: "Search with \(engine)")
        }

        let normalized = trimmed
            .replacingOccurrences(of: "...", with: "...")
            .replacingOccurrences(of: "…", with: "...")
        let map: [String: (zh: String, en: String)] = [
            "Copy": ("复制", "Copy"),
            "复制": ("复制", "Copy"),
            "Select All": ("全选", "Select All"),
            "全选": ("全选", "Select All"),
            "Look Up": ("查询", "Look Up"),
            "查询": ("查询", "Look Up"),
            "Search with Google": ("用 Google 搜索", "Search with Google"),
            "用 Google 搜索": ("用 Google 搜索", "Search with Google"),
            "Search in Spotlight": ("在 Spotlight 中搜索", "Search in Spotlight"),
            "在 Spotlight 中搜索": ("在 Spotlight 中搜索", "Search in Spotlight"),
            "Speech": ("朗读", "Speech"),
            "朗读": ("朗读", "Speech"),
            "Start Speaking": ("开始朗读", "Start Speaking"),
            "开始朗读": ("开始朗读", "Start Speaking"),
            "Stop Speaking": ("停止朗读", "Stop Speaking"),
            "停止朗读": ("停止朗读", "Stop Speaking"),
            "Services": ("服务", "Services"),
            "服务": ("服务", "Services"),
            "Open Link": ("打开链接", "Open Link"),
            "打开链接": ("打开链接", "Open Link"),
            "Copy Link": ("复制链接", "Copy Link"),
            "复制链接": ("复制链接", "Copy Link"),
            "Save Image As...": ("图像存储为...", "Save Image As..."),
            "图像存储为...": ("图像存储为...", "Save Image As..."),
            "Copy Image": ("复制图像", "Copy Image"),
            "复制图像": ("复制图像", "Copy Image"),
            "Automatically Resize": ("自动调整大小", "Automatically Resize"),
            "自动调整大小": ("自动调整大小", "Automatically Resize"),
            "Zoom In": ("放大", "Zoom In"),
            "放大": ("放大", "Zoom In"),
            "Zoom Out": ("缩小", "Zoom Out"),
            "缩小": ("缩小", "Zoom Out"),
            "Actual Size": ("实际大小", "Actual Size"),
            "实际大小": ("实际大小", "Actual Size"),
            "Single Page": ("单页", "Single Page"),
            "单页": ("单页", "Single Page"),
            "Single Page Continuous": ("单页连续", "Single Page Continuous"),
            "单页连续": ("单页连续", "Single Page Continuous"),
            "Two Pages": ("双页", "Two Pages"),
            "双页": ("双页", "Two Pages"),
            "Two Pages Continuous": ("双页连续", "Two Pages Continuous"),
            "双页连续": ("双页连续", "Two Pages Continuous"),
            "Next Page": ("下一页", "Next Page"),
            "下一页": ("下一页", "Next Page"),
            "Previous Page": ("上一页", "Previous Page"),
            "上一页": ("上一页", "Previous Page")
        ]

        guard let value = map[normalized] else { return title }
        let localized = localizedMenuTitle(zh: value.zh, en: value.en)
        if title.hasSuffix("…"), localized.hasSuffix("...") {
            return String(localized.dropLast(3)) + "…"
        }
        return localized
    }

    private func localizedMenuTitle(zh: String, en: String) -> String {
        AppText.localized(zh, en)
    }
}

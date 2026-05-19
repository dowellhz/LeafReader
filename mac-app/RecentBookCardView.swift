import Cocoa

final class RecentBookCardView: NSView {
    let path: String
    var onOpen: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    var onReveal: ((String) -> Void)?
    var onClearVectorCache: ((String) -> Void)?
    var onClearWordRecords: ((String) -> Void)?
    var onClearAIData: ((String) -> Void)?

    init(path: String) {
        self.path = path
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        path = ""
        super.init(coder: coder)
    }

    override func mouseUp(with event: NSEvent) {
        onOpen?(path)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(menuItem(title: AppText.localized("打开", "Open"), action: #selector(openFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("在 Finder 中显示", "Show in Finder"), action: #selector(revealFromMenu(_:))))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: AppText.localized("移出书架", "Remove from Shelf"), action: #selector(removeFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("清除本书 AI 阅读记录", "Clear Book AI Reading Records"), action: #selector(clearVectorCacheFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("清除本书单词记录", "Clear Book Words"), action: #selector(clearWordRecordsFromMenu(_:))))
        menu.addItem(menuItem(title: AppText.localized("清除本书 AI 数据", "Clear Book AI Data"), action: #selector(clearAIDataFromMenu(_:))))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func openFromMenu(_ sender: NSMenuItem) {
        onOpen?(path)
    }

    @objc func revealFromMenu(_ sender: NSMenuItem) {
        onReveal?(path)
    }

    @objc func removeFromMenu(_ sender: NSMenuItem) {
        onRemove?(path)
    }

    @objc func clearVectorCacheFromMenu(_ sender: NSMenuItem) {
        onClearVectorCache?(path)
    }

    @objc func clearWordRecordsFromMenu(_ sender: NSMenuItem) {
        onClearWordRecords?(path)
    }

    @objc func clearAIDataFromMenu(_ sender: NSMenuItem) {
        onClearAIData?(path)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}


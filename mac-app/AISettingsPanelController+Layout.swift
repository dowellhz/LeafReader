import Cocoa

struct AISettingsLayoutMetrics {
    let panelSize = NSSize(width: 760, height: 540)
    let cornerRadius: CGFloat = 18
    let titleTop: CGFloat = 34
    let horizontalInset: CGFloat = 44
    let labelColumnWidth: CGFloat = 110
    let fieldWidth: CGFloat = 440
    let formWidth: CGFloat = 672
    let controlHeight: CGFloat = 40
    let inputHeight: CGFloat = 36
}

extension AISettingsPanelController {
    func makeSettingsPanel(isDark: Bool) -> SettingsPanel {
        let metrics = AISettingsLayoutMetrics()
        let panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: metrics.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        return panel
    }

    func makeSettingsContentView(panel: SettingsPanel, isDark: Bool, backgroundColor: NSColor) -> NSView {
        let metrics = AISettingsLayoutMetrics()
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = backgroundColor.cgColor
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = (isDark
            ? NSColor(red: 0.32, green: 0.38, blue: 0.46, alpha: 1)
            : NSColor(red: 0.78, green: 0.82, blue: 0.90, alpha: 1)
        ).cgColor
        content.layer?.cornerRadius = metrics.cornerRadius
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = isDark ? 0.42 : 0.24
        content.layer?.shadowRadius = 32
        content.layer?.shadowOffset = CGSize(width: 0, height: -12)
        content.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        content.autoresizingMask = [.width, .height]
        content.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = content
        return content
    }
}

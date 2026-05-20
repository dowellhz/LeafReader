import Cocoa
import Sparkle

extension AppDelegate {
    @objc func showAboutLeafReader(_ sender: Any?) {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.localized("关于 Leaf Reader", "About Leaf Reader")
        window.isReleasedWhenClosed = false
        window.center()

        let theme = ReaderTheme.selected
        let backgroundColor: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
        switch theme {
        case .original:
            backgroundColor = .white
            primaryText = .labelColor
            secondaryText = NSColor(red: 0.43, green: 0.47, blue: 0.54, alpha: 1)
        case .eyeCare:
            backgroundColor = NSColor(red: 0.91, green: 0.87, blue: 0.74, alpha: 1)
            primaryText = NSColor(red: 0.16, green: 0.13, blue: 0.08, alpha: 1)
            secondaryText = NSColor(red: 0.45, green: 0.39, blue: 0.26, alpha: 1)
        case .dark:
            backgroundColor = NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1)
            primaryText = NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1)
            secondaryText = NSColor(red: 0.58, green: 0.63, blue: 0.70, alpha: 1)
        }

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = backgroundColor.cgColor
        window.contentView = content

        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(iconView)

        let nameLabel = NSTextField(labelWithString: "Leaf Reader")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 28, weight: .semibold)
        nameLabel.textColor = primaryText
        content.addSubview(nameLabel)

        let versionLabel = NSTextField(labelWithString: helpVersionText())
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 14, weight: .medium)
        versionLabel.textColor = secondaryText
        content.addSubview(versionLabel)

        let subtitleLabel = NSTextField(wrappingLabelWithString: AppText.localized("智能文档阅读与学习助手", "Smart document reading and learning assistant"))
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = secondaryText
        content.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 82),
            iconView.heightAnchor.constraint(equalToConstant: 82),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            nameLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            versionLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            versionLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 16),
            subtitleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            subtitleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28)
        ])

        aboutWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(aboutWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func aboutWindowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === aboutWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: aboutWindow)
        aboutWindow = nil
    }

}

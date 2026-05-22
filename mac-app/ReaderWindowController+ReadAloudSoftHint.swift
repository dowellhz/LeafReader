import Cocoa

extension ReaderWindowController {
    func showReadAloudSoftHint(key: String, title: String, action: @escaping () -> Void) {
        guard isAIPanelCollapsed,
              lastReadAloudSoftHintKey != key,
              let contentView = window?.contentView else {
            return
        }

        lastReadAloudSoftHintKey = key
        readAloudSoftHintDismissWorkItem?.cancel()

        let hintView = readAloudSoftHintView ?? makeReadAloudSoftHintView(in: contentView)
        hintView.title = title
        hintView.onAction = { [weak self] in
            guard let self else { return }
            self.dismissReadAloudSoftHint()
            if self.isAIPanelCollapsed {
                self.pendingAIPanelExpansionAction = action
                self.setAIPanelCollapsed(false, animated: true)
            } else {
                action()
            }
        }
        hintView.onPointerEntered = { [weak self] in
            self?.readAloudSoftHintDismissWorkItem?.cancel()
        }
        hintView.onPointerExited = { [weak self] in
            self?.scheduleReadAloudSoftHintDismiss()
        }
        hintView.applyTheme(ReaderTheme.selected)
        hintView.isHidden = false

        if hintView.alphaValue == 0 {
            hintView.animator().alphaValue = 1
        } else {
            hintView.alphaValue = 1
        }
        scheduleReadAloudSoftHintDismiss()
    }

    func dismissReadAloudSoftHint() {
        readAloudSoftHintDismissWorkItem?.cancel()
        readAloudSoftHintDismissWorkItem = nil
        guard let hintView = readAloudSoftHintView else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            hintView.animator().alphaValue = 0
        } completionHandler: {
            hintView.isHidden = true
        }
    }

    func updateReadAloudSoftHintTheme() {
        readAloudSoftHintView?.applyTheme(ReaderTheme.selected)
    }

    private func makeReadAloudSoftHintView(in contentView: NSView) -> ReadAloudSoftHintView {
        let hintView = ReadAloudSoftHintView()
        hintView.translatesAutoresizingMaskIntoConstraints = false
        hintView.alphaValue = 0
        hintView.isHidden = true
        contentView.addSubview(hintView, positioned: .above, relativeTo: contentArea)

        NSLayoutConstraint.activate([
            hintView.centerXAnchor.constraint(equalTo: contentArea.centerXAnchor),
            hintView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: -18),
            hintView.leadingAnchor.constraint(greaterThanOrEqualTo: contentArea.leadingAnchor, constant: 24),
            hintView.trailingAnchor.constraint(lessThanOrEqualTo: contentArea.trailingAnchor, constant: -24),
            hintView.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            hintView.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])
        readAloudSoftHintView = hintView
        return hintView
    }

    private func scheduleReadAloudSoftHintDismiss() {
        readAloudSoftHintDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissReadAloudSoftHint()
        }
        readAloudSoftHintDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: workItem)
    }
}

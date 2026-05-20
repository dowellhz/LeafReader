import Cocoa

extension ReaderWindowController {
    func applyReaderTheme() {
        let theme = ReaderTheme.selected
        let isDark = theme == .dark
        let chromeBackground = chromeBackgroundColor(for: theme)
        let toolbarBackground = toolbarBackgroundColor(for: theme)
        let toolbarBorder = toolbarBorderColor(for: theme)
        let controlBackground = controlBackgroundColor(for: theme)
        let controlBorder = controlBorderColor(for: theme)
        let handleColor = resizeHandleColor(for: theme)

        window?.backgroundColor = chromeBackground
        window?.appearance = isDark ? NSAppearance(named: .darkAqua) : nil
        contentArea.layer?.backgroundColor = chromeBackground.cgColor
        pdfContainer.layer?.backgroundColor = chromeBackground.cgColor
        webView.layer?.backgroundColor = chromeBackground.cgColor
        toolbarView?.layer?.backgroundColor = toolbarBackground.cgColor
        toolbarView?.layer?.borderColor = toolbarBorder.cgColor
        bottomBarView?.layer?.backgroundColor = toolbarView?.layer?.backgroundColor
        bottomBarView?.layer?.borderColor = toolbarView?.layer?.borderColor
        zoomGroupView?.layer?.backgroundColor = controlBackground.cgColor
        zoomGroupView?.layer?.borderColor = controlBorder.cgColor
        resizeHandle.layer?.backgroundColor = handleColor.cgColor
        searchUnderlineButton?.isDark = isDark
        applyChromeTheme(to: window?.contentView, theme: theme)
        updatePageLabelTextColor()
        updateEmbeddingStatusTextColor()
        aiPanel.setTheme(theme)
        searchOverlay.setTheme(theme)
        pdfView.backgroundColor = chromeBackground
        pdfView.enclosingScrollView?.backgroundColor = chromeBackground
        applyPDFReaderTheme(theme: theme)

        applyWebReaderTheme(theme: theme)
    }

    func chromeBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.90, green: 0.87, blue: 0.76, alpha: 1)
        case .dark:
            return NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
        }
    }

    func toolbarBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor.white.withAlphaComponent(0.97)
        case .eyeCare:
            return NSColor(red: 0.86, green: 0.82, blue: 0.68, alpha: 0.97)
        case .dark:
            return NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
        }
    }

    func toolbarBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.71, green: 0.66, blue: 0.50, alpha: 1)
        case .dark:
            return NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
        }
    }

    func controlBackgroundColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return .white
        case .eyeCare:
            return NSColor(red: 0.91, green: 0.87, blue: 0.73, alpha: 1)
        case .dark:
            return NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
        }
    }

    func controlBorderColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.67, green: 0.61, blue: 0.45, alpha: 1)
        case .dark:
            return NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
        }
    }

    func resizeHandleColor(for theme: ReaderTheme) -> NSColor {
        switch theme {
        case .original:
            return NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1)
        case .eyeCare:
            return NSColor(red: 0.72, green: 0.67, blue: 0.50, alpha: 1)
        case .dark:
            return NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
        }
    }

    func applyChromeTheme(to view: NSView?, theme: ReaderTheme) {
        guard let view else { return }
        let textColor: NSColor
        let secondaryColor: NSColor
        switch theme {
        case .original:
            textColor = NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
            secondaryColor = NSColor(red: 0.36, green: 0.39, blue: 0.48, alpha: 1)
        case .eyeCare:
            textColor = NSColor(red: 0.18, green: 0.15, blue: 0.09, alpha: 1)
            secondaryColor = NSColor(red: 0.45, green: 0.39, blue: 0.26, alpha: 1)
        case .dark:
            textColor = NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            secondaryColor = NSColor(red: 0.62, green: 0.67, blue: 0.74, alpha: 1)
        }

        if let label = view as? NSTextField {
            label.textColor = textColor
        }
        if let button = view as? NSButton {
            if button.identifier == Self.capsuleButtonIdentifier {
                (button as? CapsuleChromeButton)?.theme = theme
            } else {
                button.contentTintColor = secondaryColor
            }
        }
        if view !== aiPanel, view !== searchOverlay {
            for subview in view.subviews {
                applyChromeTheme(to: subview, theme: theme)
            }
        }
    }

    func updatePageLabelTextColor() {
        let isDark = ReaderTheme.selected == .dark
        if pageLabel.stringValue == AppText.noPDF {
            pageLabel.textColor = isDark
                ? NSColor(red: 0.54, green: 0.58, blue: 0.64, alpha: 1)
                : NSColor(red: 0.52, green: 0.55, blue: 0.62, alpha: 1)
        } else {
            pageLabel.textColor = isDark
                ? NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
                : NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        }
    }

    func updateEmbeddingStatusTextColor() {
        let isDark = ReaderTheme.selected == .dark
        embeddingStatusLabel.textColor = isDark
            ? NSColor(red: 0.68, green: 0.73, blue: 0.80, alpha: 1)
            : NSColor(red: 0.60, green: 0.65, blue: 0.72, alpha: 1)
    }

    func applyPDFReaderTheme(theme: ReaderTheme) {
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        clearPDFContentFilters()
        let dimming = ReaderTheme.pdfDimmingStrength
        pdfDimOverlay.isHidden = currentDocumentKind != .pdf || theme == .original || dimming <= 0
        pdfDimOverlay.layer?.backgroundColor = pdfDimmingColor(for: theme, strength: dimming).cgColor
        pdfView.documentView?.needsDisplay = true
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func clearPDFContentFilters() {
        pdfView.documentView?.layer?.filters = nil
    }

    func pdfDimmingColor(for theme: ReaderTheme, strength: Double) -> NSColor {
        switch theme {
        case .original:
            return .clear
        case .eyeCare:
            return NSColor(red: 0.76, green: 0.62, blue: 0.30, alpha: CGFloat(strength * 0.38))
        case .dark:
            return NSColor.black.withAlphaComponent(CGFloat(strength))
        }
    }

    func applyWebReaderTheme(theme: ReaderTheme = ReaderTheme.selected) {
        guard webView != nil else { return }
        let themeCSS = """
        html.leaf-reader-dark { background: #111418 !important; color-scheme: dark; }
        html.leaf-reader-dark body {
          color: #d9dee7 !important;
          background: #171a20 !important;
        }
        html.leaf-reader-dark p,
        html.leaf-reader-dark div,
        html.leaf-reader-dark span,
        html.leaf-reader-dark li,
        html.leaf-reader-dark blockquote,
        html.leaf-reader-dark td,
        html.leaf-reader-dark th,
        html.leaf-reader-dark h1,
        html.leaf-reader-dark h2,
        html.leaf-reader-dark h3,
        html.leaf-reader-dark h4,
        html.leaf-reader-dark h5,
        html.leaf-reader-dark h6,
        html.leaf-reader-dark strong,
        html.leaf-reader-dark em,
        html.leaf-reader-dark b,
        html.leaf-reader-dark i {
          color: #d9dee7 !important;
          background-color: transparent !important;
          text-shadow: none !important;
        }
        html.leaf-reader-dark body * {
          border-color: #343b46 !important;
        }
        html.leaf-reader-dark a {
          color: #9fc0ff !important;
        }
        html.leaf-reader-dark img,
        html.leaf-reader-dark svg {
          filter: brightness(.88) contrast(.98);
        }
        html.leaf-reader-dark ::selection {
          background: rgba(255, 221, 87, .46) !important;
        }
        html.leaf-reader-eye-care { background: #eee8d5 !important; color-scheme: light; }
        html.leaf-reader-eye-care body {
          color: #24261f !important;
          background: #f3eddb !important;
        }
        html.leaf-reader-eye-care p,
        html.leaf-reader-eye-care div,
        html.leaf-reader-eye-care span,
        html.leaf-reader-eye-care li,
        html.leaf-reader-eye-care blockquote,
        html.leaf-reader-eye-care td,
        html.leaf-reader-eye-care th,
        html.leaf-reader-eye-care h1,
        html.leaf-reader-eye-care h2,
        html.leaf-reader-eye-care h3,
        html.leaf-reader-eye-care h4,
        html.leaf-reader-eye-care h5,
        html.leaf-reader-eye-care h6,
        html.leaf-reader-eye-care strong,
        html.leaf-reader-eye-care em,
        html.leaf-reader-eye-care b,
        html.leaf-reader-eye-care i {
          color: #24261f !important;
          background-color: transparent !important;
          text-shadow: none !important;
        }
        html.leaf-reader-eye-care body * {
          border-color: #d8cda9 !important;
        }
        html.leaf-reader-eye-care a {
          color: #315d93 !important;
        }
        html.leaf-reader-eye-care img,
        html.leaf-reader-eye-care svg {
          filter: brightness(.94) saturate(.92) contrast(.98);
        }
        html.leaf-reader-eye-care ::selection {
          background: rgba(204, 149, 39, .30) !important;
        }
        """
        let cssLiteral = jsStringLiteral(themeCSS)
        let darkEnabled = theme == .dark ? "true" : "false"
        let eyeCareEnabled = theme == .eyeCare ? "true" : "false"
        webView.evaluateJavaScript("""
        (() => {
          const darkEnabled = \(darkEnabled);
          const eyeCareEnabled = \(eyeCareEnabled);
          let style = document.getElementById('leaf-reader-theme-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'leaf-reader-theme-style';
            document.head.appendChild(style);
          }
          style.textContent = \(cssLiteral);
          document.documentElement.classList.toggle('leaf-reader-dark', darkEnabled);
          document.documentElement.classList.toggle('leaf-reader-eye-care', eyeCareEnabled);
        })();
        """)
    }
}

import Cocoa

extension ReaderWindowController {
    func applyReaderTheme() {
        let isDark = ReaderTheme.selected == .dark
        let chromeBackground = isDark
            ? NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
            : NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)

        window?.backgroundColor = chromeBackground
        window?.appearance = isDark ? NSAppearance(named: .darkAqua) : nil
        contentArea.layer?.backgroundColor = chromeBackground.cgColor
        pdfContainer.layer?.backgroundColor = chromeBackground.cgColor
        webView.layer?.backgroundColor = chromeBackground.cgColor
        toolbarView?.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 0.96)
            : NSColor.white.withAlphaComponent(0.97)
        ).cgColor
        toolbarView?.layer?.borderColor = (isDark
            ? NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
            : NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1)
        ).cgColor
        bottomBarView?.layer?.backgroundColor = toolbarView?.layer?.backgroundColor
        bottomBarView?.layer?.borderColor = toolbarView?.layer?.borderColor
        zoomGroupView?.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1)
            : NSColor.white
        ).cgColor
        zoomGroupView?.layer?.borderColor = (isDark
            ? NSColor(red: 0.22, green: 0.27, blue: 0.33, alpha: 1)
            : NSColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1)
        ).cgColor
        resizeHandle.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.20, green: 0.24, blue: 0.29, alpha: 1)
            : NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1)
        ).cgColor
        searchUnderlineButton?.isDark = isDark
        applyChromeTheme(to: window?.contentView, isDark: isDark)
        aiPanel.setDarkMode(isDark)
        searchOverlay.setDarkMode(isDark)
        pdfView.backgroundColor = chromeBackground
        pdfView.enclosingScrollView?.backgroundColor = chromeBackground
        pdfView.documentView?.wantsLayer = true
        pdfView.documentView?.layer?.backgroundColor = chromeBackground.cgColor
        applyPDFReaderTheme(isDark: isDark)

        applyWebReaderTheme()
    }

    func applyChromeTheme(to view: NSView?, isDark: Bool) {
        guard let view else { return }
        let textColor = isDark
            ? NSColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1)
            : NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
        let secondaryColor = isDark
            ? NSColor(red: 0.62, green: 0.67, blue: 0.74, alpha: 1)
            : NSColor(red: 0.36, green: 0.39, blue: 0.48, alpha: 1)

        if let label = view as? NSTextField {
            label.textColor = textColor
        }
        if let button = view as? NSButton {
            if button.identifier == Self.capsuleButtonIdentifier {
                (button as? CapsuleChromeButton)?.isDark = isDark
            } else {
                button.contentTintColor = secondaryColor
            }
        }
        if view !== aiPanel, view !== searchOverlay {
            for subview in view.subviews {
                applyChromeTheme(to: subview, isDark: isDark)
            }
        }
    }

    func applyPDFReaderTheme(isDark: Bool) {
        guard let documentView = pdfView.documentView else { return }
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        documentView.wantsLayer = true
        documentView.layer?.backgroundColor = NSColor.clear.cgColor
        documentView.layer?.filters = []
        pdfDimOverlay.isHidden = !isDark || currentDocumentKind != .pdf
        pdfDimOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
        documentView.needsDisplay = true
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    func applyWebReaderTheme() {
        guard webView != nil else { return }
        let darkCSS = """
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
        """
        let cssLiteral = jsStringLiteral(darkCSS)
        let enabled = ReaderTheme.selected == .dark ? "true" : "false"
        webView.evaluateJavaScript("""
        (() => {
          const enabled = \(enabled);
          let style = document.getElementById('leaf-reader-theme-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'leaf-reader-theme-style';
            document.head.appendChild(style);
          }
          style.textContent = \(cssLiteral);
          document.documentElement.classList.toggle('leaf-reader-dark', enabled);
        })();
        """)
    }
}

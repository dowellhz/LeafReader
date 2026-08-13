import Cocoa

extension ReaderWindowController {
    func applyReaderTheme(refreshDocumentDecorations: Bool = true) {
        let theme = ReaderTheme.selected
        let isDark = theme == .dark
        let chromeBackground = chromeBackgroundColor(for: theme)
        let toolbarBackground = toolbarBackgroundColor(for: theme)
        let toolbarBorder = toolbarBorderColor(for: theme)
        let controlBackground = controlBackgroundColor(for: theme)
        let controlBorder = controlBorderColor(for: theme)
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
        resizeHandle.theme = theme
        searchUnderlineButton?.theme = theme
        applyChromeTheme(to: window?.contentView, theme: theme)
        updatePageLabelTextColor()
        updateEmbeddingStatusTextColor()
        aiHandleButton.theme = theme
        aiPanel.setTheme(theme)
        updateReadAloudSoftHintTheme()
        updateReadAloudFloatingControl()
        searchOverlay.setTheme(theme)
        selectionActionToolbar.applyTheme(theme)
        readingNotePanelControllers.values.forEach { $0.refreshTheme() }
        readingNotesPanelController?.refreshTheme()
        pdfView.backgroundColor = chromeBackground
        pdfView.enclosingScrollView?.backgroundColor = chromeBackground
        applyPDFReaderTheme(theme: theme, refreshReadingNotes: refreshDocumentDecorations)
        if refreshDocumentDecorations {
            refreshStoredWordAnnotationAppearance()
        }

        applyWebReaderTheme(theme: theme)
    }

    func chromeBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.chromeBackgroundColor
    }

    func toolbarBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.toolbarBackgroundColor
    }

    func toolbarBorderColor(for theme: ReaderTheme) -> NSColor {
        theme.toolbarBorderColor
    }

    func controlBackgroundColor(for theme: ReaderTheme) -> NSColor {
        theme.controlBackgroundColor
    }

    func controlBorderColor(for theme: ReaderTheme) -> NSColor {
        theme.controlBorderColor
    }

    func applyChromeTheme(to view: NSView?, theme: ReaderTheme) {
        guard let view else { return }
        if let label = view as? NSTextField {
            label.textColor = theme.primaryTextColor
        }
        if let button = view as? NSButton {
            if button.identifier == Self.capsuleButtonIdentifier {
                (button as? CapsuleChromeButton)?.theme = theme
            } else {
                button.contentTintColor = theme.secondaryTextColor
            }
        }
        if let imageView = view as? NSImageView {
            imageView.contentTintColor = theme.secondaryTextColor
        }
        if view !== aiPanel, view !== searchOverlay {
            for subview in view.subviews {
                applyChromeTheme(to: subview, theme: theme)
            }
        }
    }

    func updatePageLabelTextColor() {
        pageLabel.textColor = pageLabel.stringValue == AppText.noPDF
            ? noDocumentPageLabelTextColor(for: ReaderTheme.selected)
            : pageLabelTextColor(for: ReaderTheme.selected)
    }

    func pageLabelTextColor(for theme: ReaderTheme) -> NSColor {
        theme.primaryTextColor
    }

    func noDocumentPageLabelTextColor(for theme: ReaderTheme) -> NSColor {
        theme.mutedTextColor
    }

    func updateEmbeddingStatusTextColor() {
        embeddingStatusLabel.textColor = ReaderTheme.selected.secondaryTextColor
    }

    func applyPDFReaderTheme(theme: ReaderTheme, refreshReadingNotes: Bool = true) {
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        clearPDFContentFilters()
        let dimming = ReaderTheme.pdfDimmingStrength
        pdfDimOverlay.isHidden = currentDocumentKind != .pdf || theme == .original || dimming <= 0
        pdfDimOverlay.layer?.backgroundColor = pdfDimmingColor(for: theme, strength: dimming).cgColor
        pdfView.documentView?.needsDisplay = true
        pdfView.setNeedsDisplay(pdfView.bounds)
        updateAISourceUnderlineTheme(theme)
        if refreshReadingNotes {
            restoreReadingNoteAnnotations()
        }
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
        guard webView != nil, currentDocumentKind != .pdf, webView.isHidden == false else { return }
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
        html.leaf-reader-eye-care ::selection {
          background: rgba(204, 149, 39, .30) !important;
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
        """
        let cssLiteral = jsStringLiteral(themeCSS)
        let aiSourceUnderlineColor = jsStringLiteral(cssRGBAString(for: theme.aiSourceUnderlineColor))
        let selectionBackgroundColor = jsStringLiteral(webSelectionBackgroundCSS(for: theme))
        let readingNoteHighlightColor = jsStringLiteral(webReadingNoteHighlightCSS(for: theme))
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
          document.documentElement.style.setProperty('--leaf-reader-ai-source-underline', \(aiSourceUnderlineColor));
          document.documentElement.style.setProperty('--leaf-reader-selection-background', \(selectionBackgroundColor));
          document.documentElement.style.setProperty('--leaf-reader-note-highlight-background', \(readingNoteHighlightColor));
        })();
        """)
    }

    private func webSelectionBackgroundCSS(for theme: ReaderTheme) -> String {
        switch theme {
        case .eyeCare:
            return "rgba(204, 149, 39, .30)"
        case .dark:
            return "rgba(255, 221, 87, .46)"
        case .original:
            return "rgba(255, 221, 87, .62)"
        }
    }

    private func webReadingNoteHighlightCSS(for theme: ReaderTheme) -> String {
        switch theme {
        case .eyeCare:
            return "rgba(204, 149, 39, .30)"
        case .dark:
            return "rgba(145, 202, 255, .34)"
        case .original:
            return "rgba(145, 202, 255, .30)"
        }
    }

    func cssRGBAString(for color: NSColor) -> String {
        let rgba = color.usingColorSpace(.sRGB) ?? color
        let red = Int((rgba.redComponent * 255).rounded())
        let green = Int((rgba.greenComponent * 255).rounded())
        let blue = Int((rgba.blueComponent * 255).rounded())
        let alpha = Double(rgba.alphaComponent)
        return String(format: "rgba(%d, %d, %d, %.3f)", red, green, blue, alpha)
    }
}

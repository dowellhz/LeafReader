import Cocoa

private enum AIConversationExportFormat: Int, CaseIterable {
    case markdown
    case pdf
    case html

    var title: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .pdf:
            return "PDF"
        case .html:
            return "HTML"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .pdf:
            return "pdf"
        case .html:
            return "html"
        }
    }

    var option: ExportPanelSupport.FormatOption {
        ExportPanelSupport.FormatOption(title: title, fileExtension: fileExtension)
    }
}

extension AIChatPanel {
    @objc func copyBubbleMarkdown(_ sender: NSButton) {
        guard let bodyID = sender.identifier?.rawValue,
              let text = bubbleMetadataByID[bodyID]?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusLabel.stringValue = AppText.localized("已复制 Markdown", "Markdown copied")
    }

    @objc func exportConversationTapped(_ sender: NSButton) {
        let bubbles = exportableConversationBubbles()
        guard !bubbles.isEmpty else {
            statusLabel.stringValue = AppText.localized("当前没有可导出的对话", "No conversation to export")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = AppText.localized("导出 AI 对话", "Export AI Conversation")
        savePanel.nameFieldStringValue = defaultConversationExportFilename()
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = ExportPanelSupport.contentTypes(for: conversationExportFormatOptions())
        let formatPopup = ExportPanelSupport.popup(
            for: AIConversationExportFormat.allCases.map(\.title),
            selectedIndex: AIConversationExportFormat.markdown.rawValue
        )
        savePanel.accessoryView = ExportPanelSupport.accessoryView(rows: [
            (title: AppText.localized("文件类型：", "File type:"), control: formatPopup)
        ])
        savePanel.canCreateDirectories = true
        savePanel.begin { [weak self] response in
            guard response == .OK,
                  let url = savePanel.url else {
                return
            }
            let index = ExportPanelSupport.selectedIndex(
                from: formatPopup,
                count: AIConversationExportFormat.allCases.count,
                defaultIndex: AIConversationExportFormat.markdown.rawValue
            )
            let format = AIConversationExportFormat(rawValue: index) ?? .markdown
            self?.writeConversation(to: url, format: format, bubbles: bubbles)
        }
    }

    private func exportableConversationBubbles() -> [SavedAIConversationBubble] {
        persistentBubbleIDs.compactMap { bodyID in
            guard let metadata = bubbleMetadataByID[bodyID],
                  isConversationBubble(metadata),
                  metadata.role == AppText.userRole || metadata.role == AppText.aiRole else {
                return nil
            }
            return SavedAIConversationBubble(
                role: metadata.role,
                text: metadata.text,
                collapsible: metadata.collapsible,
                renderMarkdown: metadata.renderMarkdown,
                sourceLocation: metadata.sourceLocation
            )
        }
    }

    private func writeConversation(to url: URL, format: AIConversationExportFormat, bubbles: [SavedAIConversationBubble]) {
        let title = AppText.localized("当前文档", "Current Document")
        let outputURL = urlForConversationExport(url, format: format)
        do {
            switch format {
            case .markdown:
                let markdown = AIConversationMarkdownExporter.markdown(title: title, bubbles: bubbles)
                try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
            case .html:
                let html = AIConversationMarkdownExporter.html(title: title, bubbles: bubbles)
                try html.write(to: outputURL, atomically: true, encoding: .utf8)
            case .pdf:
                let html = AIConversationMarkdownExporter.html(title: title, bubbles: bubbles)
                let data = try ReadingNotePDFExporter.data(html: html)
                try data.write(to: outputURL, options: .atomic)
            }
            statusLabel.stringValue = AppText.localized("已导出", "Exported")
        } catch {
            statusLabel.stringValue = AppText.localized("导出失败", "Export failed")
            NSLog("LeafReader AI conversation export failed: %@", error.localizedDescription)
        }
    }

    private func defaultConversationExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "LeafReader-AI-\(formatter.string(from: Date())).md"
    }

    private func conversationExportFormatOptions() -> [ExportPanelSupport.FormatOption] {
        AIConversationExportFormat.allCases.map(\.option)
    }

    private func urlForConversationExport(_ url: URL, format: AIConversationExportFormat) -> URL {
        ExportPanelSupport.outputURL(url, matching: format.option)
    }
}

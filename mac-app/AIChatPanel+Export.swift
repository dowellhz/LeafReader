import Cocoa
import UniformTypeIdentifiers

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
        if let markdownType = UTType(filenameExtension: "md") {
            savePanel.allowedContentTypes = [markdownType]
        }
        savePanel.canCreateDirectories = true
        savePanel.begin { [weak self] response in
            guard response == .OK,
                  let url = savePanel.url else {
                return
            }
            self?.writeConversationMarkdown(to: url, bubbles: bubbles)
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

    private func writeConversationMarkdown(to url: URL, bubbles: [SavedAIConversationBubble]) {
        let title = AppText.localized("当前文档", "Current Document")
        let markdown = AIConversationMarkdownExporter.markdown(title: title, bubbles: bubbles)
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = AppText.localized("已导出 Markdown", "Markdown exported")
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
}

import Foundation

enum AIConversationMarkdownExporter {
    static func markdown(title: String, bubbles: [SavedAIConversationBubble], exportedAt: Date = Date()) -> String {
        var lines: [String] = [
            "# \(title) - \(AppText.localized("AI 对话", "AI Conversation"))",
            "",
            "- \(AppText.localized("导出时间", "Exported at"))：\(DateFormatter.localizedString(from: exportedAt, dateStyle: .medium, timeStyle: .short))",
            "- \(AppText.localized("气泡数", "Bubbles"))：\(bubbles.count)",
            ""
        ]

        for bubble in bubbles {
            let heading = headingText(for: bubble.role)
            let body = bubble.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            lines.append("## \(heading)")
            lines.append("")
            lines.append(body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func headingText(for role: String) -> String {
        if role == AppText.userRole {
            return AppText.localized("用户", "User")
        }
        if role == AppText.aiRole {
            return AppText.localized("AI", "AI")
        }
        return role
    }
}

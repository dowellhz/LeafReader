import Cocoa
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import WebKit

struct ChatMessage {
    let role: String
    let content: String
}

struct TranscriptEntry {
    let role: String
    let content: String
}

enum AppText {
    enum Language: String, CaseIterable {
        case system
        case chinese
        case english

        var title: String {
            switch self {
            case .system:
                return AppText.localized("跟随系统", "System")
            case .chinese:
                return "中文"
            case .english:
                return "English"
            }
        }
    }

    static let languageDefaultsKey = "appLanguage"

    static var selectedLanguage: Language {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: languageDefaultsKey),
                  let language = Language(rawValue: rawValue) else {
                return .system
            }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageDefaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var isChinese: Bool {
        switch selectedLanguage {
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        case .chinese:
            return true
        case .english:
            return false
        }
    }

    static func localized(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    static var askAI: String { localized("✨ 问 AI", "✨ Ask AI") }
    static var explainPrefix: String { localized("解释", "Explain") }
    static var userRole: String { localized("我", "Me") }
    static var aiRole: String { "AI" }
    static var errorRole: String { localized("错误", "Error") }
    static var none: String { localized("（暂无）", "(None)") }
    static var thinking: String { localized("正在思考...", "Thinking...") }
    static var generating: String { localized("正在生成...", "Generating...") }
    static var tapToExpand: String { localized("点击展开/收起", "Click to expand/collapse") }
    static var followUpPlaceholder: String { localized("继续追问", "Ask a follow-up") }
    static var send: String { localized("发送", "Send") }
    static var noPDF: String { localized("No PDF", "No PDF") }
    static var fullScreen: String { localized("全屏", "Full Screen") }
    static var windowed: String { localized("窗口", "Windowed") }
    static var cover: String { localized("首页", "Cover") }
    static var prev: String { localized("上一页", "Prev") }
    static var next: String { localized("下一页", "Next") }
    static var settings: String { localized("设置", "Settings") }
    static var close: String { localized("关闭", "Close") }
    static var model: String { localized("模型", "Model") }
    static var modelHelp: String { localized("选择你要使用的 AI 模型。", "Choose the AI model you want to use.") }
    static var language: String { localized("语言", "Language") }
    static var languageHelp: String { localized("选择界面语言和 AI 回答语言。", "Choose the UI language and AI response language.") }
    static var apiKeyPlaceholder: String { localized("请输入你的 API Key", "Enter your API Key") }
    static var keyHelp: String {
        localized("你的 API Key 将安全存储，仅用于你自己的请求。", "Your API Key is stored locally and only used for your own requests.")
    }
    static var showAPIKey: String { localized("显示 API Key", "Show API Key") }
    static var hideAPIKey: String { localized("隐藏 API Key", "Hide API Key") }
    static var cancel: String { localized("取消", "Cancel") }
    static var confirm: String { localized("确认", "Confirm") }

    static func systemPrompt() -> String {
        if isChinese {
            return """
            你是一名英语学习助手。

            规则如下：

            如果用户输入的是单个单词或短词组：
            解释中文意思
            说明词性（如名词、动词、形容词等）
            给 1～2 个简单自然的英文例句
            不需要过度展开

            如果用户输入的是完整句子或长段落：
            按句子或自然语义块逐段处理
            每段先输出原文，原文必须单独一行并用 Markdown 粗体格式 **原文** 包起来
            再给出自然中文翻译
            再解析其中较难的单词、短语、俚语或固定搭配
            简单基础词汇无需解释
            重点解释地道表达、固定搭配、语法难点、文化语境

            输出风格：
            简洁清晰
            不要长篇英语语法教学
            优先帮助用户“看懂”和“会用”
            默认以美式日常英语为主进行解释
            """
        }
        return """
        You are an English reading and vocabulary assistant.

        Rules:

        If the user provides a single word or short phrase:
        Explain the meaning in clear English.
        Include the part of speech.
        Give 1-2 simple, natural English examples.
        Keep the answer concise.

        If the user provides a full sentence or longer passage:
        Process it by sentence or natural meaning block.
        First output the original source text on its own line, wrapped in Markdown bold like **Original text**.
        Then give a plain-English explanation or paraphrase.
        Then explain difficult words, phrases, idioms, grammar points, and cultural context.
        Do not explain very basic words.

        Style:
        Be concise and practical.
        Focus on helping the user understand and use the English naturally.
        Prefer everyday American English explanations.
        """
    }

    static func wordPrompt(for word: String, context: String = "") -> String {
        if isChinese {
            return """
            翻译下单词：\(word)

            这个词在文章中的上下文：
            \(context.isEmpty ? "（无）" : context)

            必须严格按下面 Markdown 格式输出，内容简洁，不要额外展开：

            # \(word)

            ## 发音：

            * 英 /.../
            * 美 /.../

            意思：中文核心意思；常见引申义

            ## 常见用法：

            ### 1. 用法名称

            * English example.

              （中文翻译）

            ### 2. 用法名称

            * English example.

              （中文翻译）

            ### 3. 用法名称

            * English example.

              （中文翻译）

            ## 词性：

            * 词性中文（part of speech）

            要求：
            - 必须优先结合上下文解释这个词在原文里的意思
            - 如果有多个常见词性，可以列出多个
            - 音标必须放在最前面，紧跟单词标题后
            - 例句要自然、简单、贴近日常使用
            - 默认以美式日常英语为主
            - 不要使用 Markdown 表格
            """
        }
        return """
        Explain this word: \(word)

        Context from the article:
        \(context.isEmpty ? "(None)" : context)

        Use this exact Markdown structure. Keep it concise:

        # \(word)

        ## Pronunciation:

        * UK /.../
        * US /.../

        Meaning: core meaning and common extended meanings

        ## Common uses:

        ### 1. Use name

        * English example.

          Short explanation.

        ### 2. Use name

        * English example.

          Short explanation.

        ### 3. Use name

        * English example.

          Short explanation.

        ## Part of speech:

        * part of speech

        Requirements:
        - Prioritize the meaning of this word in the article context.
        - List multiple common parts of speech when needed.
        - Put pronunciation first, directly after the word title.
        - Use natural, simple, everyday examples.
        - Prefer everyday American English.
        - Do not use Markdown tables.
        """
    }

    static func sentencePrompt(for text: String) -> String {
        if isChinese {
            return """
            你是英语老师，翻译下那段文字。

            格式要求：
            - 按句子或自然语义块逐段处理
            - 每段先放原文，原文必须单独一行并用 Markdown 粗体格式 **原文** 包起来
            - 下一行放自然中文翻译
            - 然后用 Markdown 项目符号解释重点词、短语、固定搭配、文化背景
            - 项目符号格式使用：* xxx：解释
            - 重要补充说明也用 Markdown 项目符号，不要写成长段
            - 不解释简单基础词
            - 不要长篇语法教学
            - 不要使用 Markdown 表格

            需要翻译和解释的英文：

            \(text)
            """
        }
        return """
        You are an English teacher. Explain this passage.

        Format requirements:
        - Process it by sentence or natural meaning block.
        - Put the original source text first, on its own line, wrapped in Markdown bold like **Original text**.
        - On the next line, give a natural plain-English explanation or paraphrase.
        - Then use Markdown bullets to explain important words, phrases, idioms, grammar, or cultural context.
        - Use bullet format: * xxx: explanation
        - Keep explanations concise.
        - Do not explain very basic words.
        - Do not use Markdown tables.

        English text to explain:

        \(text)
        """
    }

    static func followUpPrompt(context: String, text: String) -> String {
        if isChinese {
            return """
            下面是右侧 AI view 里已经展示给用户的上下文。请把它作为本次继续追问的上下文来回答，不要重复整段历史，除非用户明确要求。

            【AI view 上下文】
            \(context)

            【用户继续追问】
            \(text)
            """
        }
        return """
        Below is the context already shown in the AI view. Use it as context for this follow-up answer. Do not repeat the full history unless the user asks.

        [AI view context]
        \(context)

        [User follow-up]
        \(text)
        """
    }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class GradientButton: NSButton {
    var previewText = "" {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 18, yRadius: 18)
        let alpha: CGFloat = isEnabled ? 1 : 0.42
        let gradient = NSGradient(colors: [
            NSColor(red: 0.45, green: 0.18, blue: 0.96, alpha: alpha),
            NSColor(red: 0.21, green: 0.50, blue: 0.98, alpha: alpha)
        ])
        gradient?.draw(in: path, angle: 0)

        if isEnabled {
            NSColor(red: 0.25, green: 0.33, blue: 0.92, alpha: 0.24).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let title = AppText.askAI
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let previewAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86)
        ]

        let leftPadding: CGFloat = 18
        let gap: CGFloat = 10
        let rightPadding: CGFloat = 16
        let titleSize = title.size(withAttributes: titleAttrs)
        let midY = (bounds.height - titleSize.height) / 2 + 1
        title.draw(at: NSPoint(x: leftPadding, y: midY), withAttributes: titleAttrs)

        let preview = singleLinePreview(previewText)
        guard !preview.isEmpty else { return }

        let previewX = leftPadding + titleSize.width + gap
        let previewWidth = max(0, bounds.width - previewX - rightPadding)
        guard previewWidth > 12 else { return }
        let previewRect = NSRect(
            x: previewX,
            y: (bounds.height - 17) / 2,
            width: previewWidth,
            height: 17
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.maximumLineHeight = 17

        var attrs = previewAttrs
        attrs[.paragraphStyle] = paragraph
        (preview as NSString).draw(in: previewRect, withAttributes: attrs)
    }

    private func singleLinePreview(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class SideHandleButton: NSButton {
    static let handleWidth: CGFloat = 14
    static let handleHeight: CGFloat = 50

    var collapsedStyle = true {
        didSet { needsDisplay = true }
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        let fill = collapsedStyle
            ? NSColor(red: isHighlighted ? 0.92 : 0.98, green: isHighlighted ? 0.16 : 0.24, blue: isHighlighted ? 0.17 : 0.24, alpha: 1)
            : NSColor(red: 0.22, green: 0.50, blue: 0.98, alpha: 1)
        fill.setFill()
        path.fill()

        let symbol = collapsedStyle ? "‹" : "›"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        let size = symbol.size(withAttributes: attrs)
        symbol.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2 + 1), withAttributes: attrs)
    }
}

final class ResizeHandleView: NSView {
    var onDragDeltaX: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1).cgColor
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDragged(with event: NSEvent) {
        onDragDeltaX?(event.deltaX)
    }
}

final class ClippingView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum ReaderDocumentKind {
    case pdf
    case epub
    case docx

    static func kind(for url: URL) -> ReaderDocumentKind? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "docx":
            return .docx
        default:
            return nil
        }
    }
}

struct WebReadableDocument {
    let html: String
    let baseURL: URL
    let plainText: String
}

enum WebDocumentLoader {
    static func load(url: URL) throws -> WebReadableDocument {
        switch ReaderDocumentKind.kind(for: url) {
        case .epub:
            return try loadEPUB(url: url)
        case .docx:
            return try loadDOCX(url: url)
        default:
            throw NSError(domain: "LeafReader", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported document type"
            ])
        }
    }

    private static func loadEPUB(url: URL) throws -> WebReadableDocument {
        let directory = try unzip(url: url)
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        let containerXML = try String(contentsOf: containerURL, encoding: .utf8)
        guard let opfPath = firstXMLAttribute("full-path", in: containerXML) else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid EPUB container"
            ])
        }

        let opfURL = directory.appendingPathComponent(opfPath)
        let opfDirectory = opfURL.deletingLastPathComponent()
        let opfXML = try String(contentsOf: opfURL, encoding: .utf8)
        let manifest = epubManifest(from: opfXML)
        let spineIDs = epubSpineIDs(from: opfXML)

        var sections: [String] = []
        var plainTextParts: [String] = []
        for id in spineIDs {
            guard let href = manifest[id] else { continue }
            let chapterURL = opfDirectory.appendingPathComponent(href.removingPercentEncoding ?? href)
            guard let chapter = try? String(contentsOf: chapterURL, encoding: .utf8) else { continue }
            sections.append(rewriteRelativeLinks(in: chapter, baseURL: chapterURL.deletingLastPathComponent()))
            plainTextParts.append(htmlToPlainText(chapter))
        }

        let body = sections.isEmpty ? "<p>Unable to read EPUB content.</p>" : sections.joined(separator: "\n<hr>\n")
        return WebReadableDocument(html: pageHTML(title: url.deletingPathExtension().lastPathComponent, body: body), baseURL: opfDirectory, plainText: plainTextParts.joined(separator: "\n\n"))
    }

    private static func loadDOCX(url: URL) throws -> WebReadableDocument {
        let directory = try unzip(url: url)
        let documentURL = directory.appendingPathComponent("word/document.xml")
        let xml = try String(contentsOf: documentURL, encoding: .utf8)
        let body = docxParagraphs(from: xml)
            .map { "<p>\(escapeHTML($0))</p>" }
            .joined(separator: "\n")
        let title = url.deletingPathExtension().lastPathComponent
        let plainText = docxParagraphs(from: xml).joined(separator: "\n\n")
        return WebReadableDocument(html: pageHTML(title: title, body: body.isEmpty ? "<p>Unable to read DOCX content.</p>" : body), baseURL: directory, plainText: plainText)
    }

    private static func unzip(url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", url.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LeafReader", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Unable to unpack \(url.lastPathComponent)"
            ])
        }
        return destination
    }

    private static func epubManifest(from xml: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"<item\b[^>]*\bid=["']([^"']+)["'][^>]*\bhref=["']([^"']+)["'][^>]*/?>"#
        for match in regexMatches(pattern, in: xml) where match.count >= 3 {
            result[match[1]] = match[2]
        }
        return result
    }

    private static func epubSpineIDs(from xml: String) -> [String] {
        let pattern = #"<itemref\b[^>]*\bidref=["']([^"']+)["'][^>]*/?>"#
        return regexMatches(pattern, in: xml).compactMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func firstXMLAttribute(_ attribute: String, in xml: String) -> String? {
        let pattern = #"\#(attribute)=["']([^"']+)["']"#
        return regexMatches(pattern, in: xml).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    private static func docxParagraphs(from xml: String) -> [String] {
        let paragraphMatches = regexMatches(#"<w:p\b[\s\S]*?</w:p>"#, in: xml).compactMap(\.first)
        return paragraphMatches.map { paragraph in
            regexMatches(#"<w:t\b[^>]*>([\s\S]*?)</w:t>"#, in: paragraph)
                .compactMap { $0.count > 1 ? decodeXML($0[1]) : nil }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private static func rewriteRelativeLinks(in html: String, baseURL: URL) -> String {
        var output = html
        let base = baseURL.absoluteString
        output = output.replacingOccurrences(of: #"(?i)(src|href)=["'](?![a-z]+:|#|/)([^"']+)["']"#, with: "$1=\"\(base)/$2\"", options: .regularExpression)
        return output
    }

    private static func pageHTML(title: String, body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html { background: #f6f8fb; }
            body { max-width: 820px; margin: 0 auto; padding: 56px 64px 96px; color: #191b20; background: white; font: 18px/1.72 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; }
            h1, h2, h3 { line-height: 1.28; margin: 1.5em 0 .5em; }
            p { margin: 0 0 1em; }
            img { max-width: 100%; height: auto; }
            hr { border: 0; border-top: 1px solid #e5e7eb; margin: 2.4em 0; }
            ::selection { background: rgba(255, 221, 87, .62); }
          </style>
          <title>\(escapeHTML(title))</title>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    private static func htmlToPlainText(_ html: String) -> String {
        decodeXML(html
            .replacingOccurrences(of: #"<script\b[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style\b[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
        }
    }

    private static func decodeXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

final class EdgePagingPDFView: PDFView {
    enum ScrollPageDirection {
        case previous
        case next
    }

    var onScrollPastPageEdge: ((ScrollPageDirection) -> Void)?

    private var accumulatedEdgeScroll: CGFloat = 0
    private var lastEdgePageTurn = Date.distantPast

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)

        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(event.scrollingDeltaX), abs(deltaY) > 0 else {
            accumulatedEdgeScroll = 0
            return
        }

        let direction: ScrollPageDirection?
        if deltaY > 0, isScrolledToBottom {
            direction = .next
        } else if deltaY < 0, isScrolledToTop {
            direction = .previous
        } else {
            accumulatedEdgeScroll = 0
            direction = nil
        }

        guard let direction else { return }
        accumulatedEdgeScroll += abs(deltaY)
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 10 : 1
        guard accumulatedEdgeScroll >= threshold else { return }

        let now = Date()
        guard now.timeIntervalSince(lastEdgePageTurn) > 0.45 else { return }
        lastEdgePageTurn = now
        accumulatedEdgeScroll = 0
        onScrollPastPageEdge?(direction)
    }

    private var isScrolledToTop: Bool {
        guard let scrollView = pdfScrollView else { return false }
        return scrollView.contentView.bounds.minY <= 2
    }

    private var isScrolledToBottom: Bool {
        guard let scrollView = pdfScrollView else { return false }
        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return true }
        let clipHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        guard documentHeight > clipHeight + 2 else { return true }
        return clipView.bounds.maxY >= documentHeight - 2
    }

    private var pdfScrollView: NSScrollView? {
        if let scrollView = enclosingScrollView {
            return scrollView
        }
        return firstScrollView(in: self)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}

final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class APIKeySecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteFromClipboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
        } else {
            stringValue += text
        }
    }
}

final class APIKeyTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            pasteFromClipboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
        } else {
            stringValue += text
        }
    }
}

struct AIModelConfig {
    let id: String
    let provider: String
    let displayName: String
    let endpoint: URL
    let model: String
    let supportsThinkingToggle: Bool
}

enum LocalEncryptedStore {
    static func string(forKey key: String) -> String {
        guard
            let encoded = UserDefaults.standard.string(forKey: key),
            let data = Data(base64Encoded: encoded),
            let sealedBox = try? AES.GCM.SealedBox(combined: data),
            let decrypted = try? AES.GCM.open(sealedBox, using: encryptionKey),
            let value = String(data: decrypted, encoding: .utf8)
        else {
            return ""
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func save(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        if let sealedBox = try? AES.GCM.seal(Data(trimmed.utf8), using: encryptionKey),
           let combined = sealedBox.combined {
            UserDefaults.standard.set(combined.base64EncodedString(), forKey: key)
        }
    }

    private static var encryptionKey: SymmetricKey {
        let material = [
            "LeafReaderLocalEncryptedAPIKey",
            Bundle.main.bundleIdentifier ?? "com.linlu.leafreader",
            NSUserName(),
            NSHomeDirectory()
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }
}

enum AISettingsStore {
    static let selectedModelKey = "selectedAIModelID"

    static let models: [AIModelConfig] = [
        AIModelConfig(
            id: "deepseek-v4-flash",
            provider: "deepseek",
            displayName: "DeepSeek V4 Flash",
            endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
            model: "deepseek-v4-flash",
            supportsThinkingToggle: true
        ),
        AIModelConfig(
            id: "deepseek-v4-pro",
            provider: "deepseek",
            displayName: "DeepSeek V4 Pro",
            endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
            model: "deepseek-v4-pro",
            supportsThinkingToggle: true
        ),
        AIModelConfig(
            id: "minimax-m2-7",
            provider: "minimax",
            displayName: "MiniMax M2.7",
            endpoint: URL(string: "https://api.minimaxi.com/v1/chat/completions")!,
            model: "MiniMax-M2.7",
            supportsThinkingToggle: false
        ),
        AIModelConfig(
            id: "openai-gpt-4o",
            provider: "openai",
            displayName: "OpenAI GPT-4o",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            model: "gpt-4o",
            supportsThinkingToggle: false
        ),
        AIModelConfig(
            id: "openai-gpt-4-1",
            provider: "openai",
            displayName: "OpenAI GPT-4.1",
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            model: "gpt-4.1",
            supportsThinkingToggle: false
        ),
        AIModelConfig(
            id: "claude-3-5-sonnet",
            provider: "claude",
            displayName: "Claude 3.5 Sonnet",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            model: "claude-3-5-sonnet-latest",
            supportsThinkingToggle: false
        ),
        AIModelConfig(
            id: "claude-3-5-haiku",
            provider: "claude",
            displayName: "Claude 3.5 Haiku",
            endpoint: URL(string: "https://api.anthropic.com/v1/messages")!,
            model: "claude-3-5-haiku-latest",
            supportsThinkingToggle: false
        )
    ]

    static var selectedModel: AIModelConfig {
        let selectedID = UserDefaults.standard.string(forKey: selectedModelKey)
        return models.first { $0.id == selectedID } ?? models[0]
    }

    static var hasAPIKeyForSelectedModel: Bool {
        !apiKey(for: selectedModel).isEmpty
    }

    static func apiKey(for config: AIModelConfig) -> String {
        let key = LocalEncryptedStore.string(forKey: encryptedAPIKeyDefaultsKey(for: config.provider))
        if !key.isEmpty {
            return key
        }

        if let legacyKey = UserDefaults.standard.string(forKey: apiKeyDefaultsKey(for: config.provider))?.trimmingCharacters(in: .whitespacesAndNewlines), !legacyKey.isEmpty {
            LocalEncryptedStore.save(legacyKey, forKey: encryptedAPIKeyDefaultsKey(for: config.provider))
            UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey(for: config.provider))
            UserDefaults.standard.synchronize()
            return legacyKey
        }

        return ""
    }

    static func save(modelID: String, apiKey: String) {
        guard let model = models.first(where: { $0.id == modelID }) else { return }
        UserDefaults.standard.set(modelID, forKey: selectedModelKey)
        LocalEncryptedStore.save(apiKey, forKey: encryptedAPIKeyDefaultsKey(for: model.provider))
        UserDefaults.standard.removeObject(forKey: apiKeyDefaultsKey(for: model.provider))
        UserDefaults.standard.synchronize()
    }

    static func apiKeyDefaultsKey(for provider: String) -> String {
        "apiKey.\(provider)"
    }

    static func encryptedAPIKeyDefaultsKey(for provider: String) -> String {
        "encryptedApiKey.\(provider)"
    }
}

final class AIClient {

    func send(messages: [ChatMessage], completion: @escaping (Result<String, Error>) -> Void) {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        Self.configureHeaders(for: config, apiKey: apiKey, request: &request)
        let payload = Self.payload(for: config, messages: messages, stream: false)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(NSError(domain: config.provider, code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "\(config.displayName) HTTP \(http.statusCode): \(body)"
                ])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: config.provider, code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No response data"
                ])))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let content = Self.responseText(from: json, provider: config.provider) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw NSError(domain: config.provider, code: -2, userInfo: [
                        NSLocalizedDescriptionKey: "Unexpected response: \(body)"
                    ])
                }
                completion(.success(Self.visibleAnswer(from: content)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func sendStream(
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let config = AISettingsStore.selectedModel
        let apiKey = AISettingsStore.apiKey(for: config)
        guard !apiKey.isEmpty else {
            completion(.failure(Self.missingAPIKeyError(for: config)))
            return
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        Self.configureHeaders(for: config, apiKey: apiKey, request: &request)
        let payload = Self.payload(for: config, messages: messages, stream: true)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        Task {
            var fullText = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: config.provider, code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid response"
                    ])
                }
                guard (200...299).contains(http.statusCode) else {
                    var body = ""
                    for try await line in bytes.lines {
                        body += line
                    }
                    throw NSError(domain: config.provider, code: http.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "\(config.displayName) HTTP \(http.statusCode): \(body)"
                    ])
                }

                for try await line in bytes.lines {
                    guard let delta = Self.deltaText(fromStreamLine: line, provider: config.provider), !delta.isEmpty else { continue }
                    fullText += delta
                    onDelta(delta)
                }

                completion(.success(Self.visibleAnswer(from: fullText)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func configureHeaders(for config: AIModelConfig, apiKey: String, request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.provider == "claude" {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func payload(for config: AIModelConfig, messages: [ChatMessage], stream: Bool) -> [String: Any] {
        if config.provider == "claude" {
            let system = messages
                .filter { $0.role == "system" }
                .map(\.content)
                .joined(separator: "\n\n")
            let claudeMessages = messages
                .filter { $0.role != "system" }
                .map { message in
                    [
                        "role": message.role == "assistant" ? "assistant" : "user",
                        "content": [["type": "text", "text": message.content]]
                    ] as [String: Any]
                }
            var payload: [String: Any] = [
                "model": config.model,
                "max_tokens": 2048,
                "messages": claudeMessages,
                "stream": stream
            ]
            if !system.isEmpty {
                payload["system"] = system
            }
            return payload
        }

        var payload: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": 0.4,
            "max_tokens": 2048
        ]
        if stream {
            payload["stream"] = true
        }
        if config.supportsThinkingToggle {
            payload["thinking"] = ["type": "disabled"]
        }
        return payload
    }

    private static func responseText(from json: [String: Any]?, provider: String) -> String? {
        guard let json else { return nil }
        if provider == "claude" {
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { block in
                block["text"] as? String
            }.joined()
        }

        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return nil
        }
        return content
    }

    private static func deltaText(fromStreamLine line: String, provider: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let jsonString: String
        if trimmed.hasPrefix("data:") {
            jsonString = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            jsonString = trimmed
        }
        if jsonString == "[DONE]" { return nil }
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
            if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
                return content
            }
            if let delta = first["delta"] as? [String: Any],
               delta["reasoning_content"] as? String != nil {
                return nil
            }
            if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
            if let message = first["message"] as? [String: Any],
               message["reasoning_content"] as? String != nil {
                return nil
            }
            if let text = first["text"] as? String {
                return text
            }
        }

        if provider == "claude",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return text
        }

        if json["reasoning_content"] as? String != nil {
            return nil
        }
        if let content = json["content"] as? String {
            return content
        }
        return nil
    }

    private static func missingAPIKeyError(for config: AIModelConfig) -> NSError {
        NSError(domain: config.provider, code: -10, userInfo: [
            NSLocalizedDescriptionKey: "Missing API key for \(config.displayName). Open settings and configure the API key."
        ])
    }

    static func visibleAnswer(from content: String) -> String {
        content
            .replacingOccurrences(of: #"(?s)<think>.*?(</think>|$)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<reasoning>.*?(</reasoning>|$)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class AIChatPanel: NSView, NSTextFieldDelegate {
    private let client = AIClient()
    private let askButton = GradientButton(title: "", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let transcriptStack = FlippedStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let inputBar = NSView()
    private let inputField = NSTextField(string: "")
    private let sendButton = NSButton(title: "", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    var onAskSelectedText: ((String) -> String?)?
    var onSettingsRequired: (() -> Void)?

    private var selectedText = ""
    private var transcriptEntries: [TranscriptEntry] = []
    private var messages: [ChatMessage] = [
        ChatMessage(role: "system", content: AppText.systemPrompt())
    ]
    private var isBusy = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedText(_ text: String) {
        selectedText = text
        askButton.previewText = text
        askButton.isEnabled = !text.isEmpty
    }

    func setContentVisible(_ visible: Bool) {
        subviews.forEach { $0.isHidden = !visible }
        layer?.backgroundColor = visible
            ? NSColor.white.withAlphaComponent(0.97).cgColor
            : NSColor.clear.cgColor
        needsLayout = true
    }

    @objc private func startQuestion() {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }

        let selectedContext = onAskSelectedText?(text) ?? nil
        let prompt = isSingleEnglishWord(text) ? wordPrompt(for: text, context: selectedContext ?? "") : sentencePrompt(for: text)
        let displayedQuestion = "\(AppText.explainPrefix): \(text)"
        appendBubble(role: AppText.userRole, text: displayedQuestion, collapsible: true)
        recordTranscript(role: AppText.userRole, text: displayedQuestion)
        messages.append(ChatMessage(role: "user", content: prompt))
        requestAI()
    }

    private func isSingleEnglishWord(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z][A-Za-z'-]*$"#, options: .regularExpression) != nil
    }

    private func wordPrompt(for word: String, context: String) -> String {
        AppText.wordPrompt(for: word, context: context)
    }

    private func sentencePrompt(for text: String) -> String {
        AppText.sentencePrompt(for: text)
    }

    @objc private func sendFollowUp() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard AISettingsStore.hasAPIKeyForSelectedModel else {
            onSettingsRequired?()
            return
        }

        inputField.stringValue = ""
        appendBubble(role: AppText.userRole, text: text, collapsible: false)
        recordTranscript(role: AppText.userRole, text: text)
        messages.append(ChatMessage(role: "user", content: followUpPrompt(for: text)))
        requestAI()
    }

    private func followUpPrompt(for text: String) -> String {
        AppText.followUpPrompt(context: transcriptContext(), text: text)
    }

    private func transcriptContext() -> String {
        guard !transcriptEntries.isEmpty else { return AppText.none }
        let context = transcriptEntries.map { entry in
            "\(entry.role)：\n\(entry.content)"
        }.joined(separator: "\n\n")
        return String(context.suffix(1000))
    }

    private func recordTranscript(role: String, text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        transcriptEntries.append(TranscriptEntry(role: role, content: content))
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === inputField else { return }
        if let movement = obj.userInfo?["NSTextMovement"] as? Int, movement == NSReturnTextMovement {
            sendFollowUp()
        }
    }

    private func requestAI() {
        setBusy(true, text: AppText.thinking)
        let assistantBody = appendBubble(role: AppText.aiRole, text: AppText.generating)
        var streamedText = ""
        client.sendStream(messages: messages, onDelta: { [weak self, weak assistantBody] delta in
            DispatchQueue.main.async {
                guard let self = self, let assistantBody = assistantBody else { return }
                streamedText += delta
                let visibleText = AIClient.visibleAnswer(from: streamedText)
                self.updateBubble(assistantBody, role: AppText.aiRole, text: visibleText.isEmpty ? AppText.generating : visibleText)
            }
        }, completion: { [weak self, weak assistantBody] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false, text: "")
                switch result {
                case .success(let content):
                    self.recordTranscript(role: AppText.aiRole, text: content)
                    self.messages.append(ChatMessage(role: "assistant", content: content))
                    if let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.aiRole, text: content)
                    }
                case .failure(let error):
                    let message = self.userFacingAIError(error)
                    if streamedText.isEmpty, let assistantBody = assistantBody {
                        self.updateBubble(assistantBody, role: AppText.errorRole, text: message)
                    } else {
                        self.appendBubble(role: AppText.errorRole, text: message)
                    }
                }
            }
        })
    }

    private func userFacingAIError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == -10 {
            return AppText.localized(
                "还没有配置当前模型的 API Key。请先打开设置，选择模型并填写 API Key。",
                "The current model does not have an API Key yet. Open Settings, choose a model, and enter the API Key."
            )
        }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return AppText.localized("网络不可用。请检查网络连接后再试。", "Network is unavailable. Check your connection and try again.")
            case NSURLErrorTimedOut:
                return AppText.localized("请求超时了。请稍后再试，或切换到响应更快的模型。", "The request timed out. Try again later, or switch to a faster model.")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return AppText.localized("无法连接到模型服务。请检查网络，或确认当前模型服务可用。", "Cannot connect to the model service. Check your network or confirm the service is available.")
            default:
                return AppText.localized("请求模型服务失败。请检查网络和 API Key 后再试。", "The model request failed. Check your network and API Key, then try again.")
            }
        }

        if nsError.code == 401 || nsError.code == 403 {
            return AppText.localized("API Key 无效或没有权限。请在设置里检查 API Key 和所选模型。", "The API Key is invalid or lacks permission. Check the API Key and selected model in Settings.")
        }
        if nsError.code == 402 {
            return AppText.localized("账户余额不足或计费不可用。请检查对应模型服务账户。", "The account balance is insufficient or billing is unavailable. Check the account for this model service.")
        }
        if nsError.code == 404 {
            return AppText.localized("当前模型不可用。请在设置里切换模型后再试。", "The selected model is unavailable. Switch models in Settings and try again.")
        }
        if nsError.code == 429 {
            return AppText.localized("请求太频繁或额度已达上限。请稍后再试。", "Too many requests or the quota has been reached. Try again later.")
        }
        if (500...599).contains(nsError.code) {
            return AppText.localized("模型服务暂时异常。请稍后再试，或切换其他模型。", "The model service is temporarily unavailable. Try again later or switch models.")
        }

        return AppText.localized("AI 请求失败。请检查模型设置、API Key 和网络后再试。", "The AI request failed. Check the model settings, API Key, and network, then try again.")
    }

    private func setBusy(_ busy: Bool, text: String) {
        isBusy = busy
        askButton.isEnabled = !busy && !selectedText.isEmpty
        inputField.isEnabled = !busy
        sendButton.isEnabled = !busy
        statusLabel.stringValue = text
        if busy {
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
    }

    @discardableResult
    private func appendBubble(role: String, text: String, collapsible: Bool = false) -> NSTextField {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = NSColor(red: 0.87, green: 0.89, blue: 0.92, alpha: 1)
        box.cornerRadius = 8
        box.fillColor = role == AppText.userRole ? NSColor(red: 0.92, green: 0.96, blue: 1, alpha: 1) : .white
        box.translatesAutoresizingMaskIntoConstraints = false

        let body = NSTextField(wrappingLabelWithString: "")
        body.attributedStringValue = role == AppText.aiRole ? markdownString(text) : plainString(text)
        body.maximumNumberOfLines = collapsible ? 1 : 0
        body.isSelectable = false
        body.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(body)
        transcriptStack.addArrangedSubview(box)
        if collapsible {
            box.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggleCollapsedBubble(_:))))
            box.toolTip = AppText.tapToExpand
        }

        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor),
            body.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12)
        ])

        DispatchQueue.main.async { [weak self, weak box] in
            guard let self = self, let box = box else { return }
            self.transcriptStack.layoutSubtreeIfNeeded()
            box.scrollToVisible(box.bounds)
        }
        return body
    }

    private func updateBubble(_ body: NSTextField, role: String, text: String) {
        body.attributedStringValue = role == AppText.aiRole ? markdownString(text) : plainString(text)
        body.invalidateIntrinsicContentSize()
        body.superview?.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
        body.superview?.scrollToVisible(body.superview?.bounds ?? body.bounds)
    }

    @objc private func toggleCollapsedBubble(_ recognizer: NSClickGestureRecognizer) {
        guard
            let box = recognizer.view as? NSBox,
            let body = box.subviews.compactMap({ $0 as? NSTextField }).first
        else { return }

        body.maximumNumberOfLines = body.maximumNumberOfLines == 1 ? 0 : 1
        body.invalidateIntrinsicContentSize()
        box.invalidateIntrinsicContentSize()
        transcriptStack.layoutSubtreeIfNeeded()
        box.scrollToVisible(box.bounds)
    }

    private func plainString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1),
            .paragraphStyle: paragraphStyle(spacing: 4)
        ])
    }

    private func markdownString(_ text: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                output.append(NSAttributedString(string: "\n"))
                continue
            }

            let cleaned = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")

            let isHeading = (cleaned.hasPrefix("【") && cleaned.contains("】")) || cleaned.hasPrefix("#")
            let isBoldLine = (line.hasPrefix("**") && line.hasSuffix("**")) || (line.hasPrefix("__") && line.hasSuffix("__"))
            let isBullet = cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") || cleaned.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            let display = cleaned
                .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[-*]\s+"#, with: "• ", options: .regularExpression)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: (isHeading || isBoldLine) ? NSFont.boldSystemFont(ofSize: isHeading ? 15 : 14) : NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1),
                .paragraphStyle: paragraphStyle(spacing: isHeading ? 7 : 4, headIndent: isBullet ? 14 : 0)
            ]
            output.append(NSAttributedString(string: display + "\n", attributes: attrs))
        }

        return output
    }

    private func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        return style
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor

        askButton.target = self
        askButton.action = #selector(startQuestion)
        askButton.isBordered = false
        askButton.isEnabled = false
        askButton.wantsLayer = true
        askButton.layer?.shadowColor = NSColor(red: 0.22, green: 0.32, blue: 0.92, alpha: 1).cgColor
        askButton.layer?.shadowOpacity = 0.24
        askButton.layer?.shadowRadius = 9
        askButton.layer?.shadowOffset = CGSize(width: 0, height: -3)
        askButton.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        transcriptStack.orientation = .vertical
        transcriptStack.alignment = .leading
        transcriptStack.spacing = 10
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = transcriptStack

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor(red: 0.42, green: 0.44, blue: 0.49, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        inputBar.wantsLayer = true
        inputBar.layer?.backgroundColor = NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1).cgColor
        inputBar.layer?.cornerRadius = 8
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        inputField.placeholderString = AppText.followUpPlaceholder
        inputField.font = NSFont.systemFont(ofSize: 14)
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(sendFollowUp)
        inputField.translatesAutoresizingMaskIntoConstraints = false

        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendFollowUp)
        sendButton.contentTintColor = NSColor(red: 0.0, green: 0.35, blue: 0.9, alpha: 1)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
        for view in [askButton, scrollView, spinner, statusLabel, inputBar] {
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            askButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            askButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            askButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            askButton.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: askButton.bottomAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            transcriptStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            transcriptStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            transcriptStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            transcriptStack.bottomAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.bottomAnchor),
            transcriptStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            spinner.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -10),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            inputBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            inputBar.heightAnchor.constraint(equalToConstant: 44),

            inputField.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    func refreshLanguage() {
        inputField.placeholderString = AppText.followUpPlaceholder
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: AppText.send)
        askButton.needsDisplay = true
        if !messages.isEmpty, messages[0].role == "system" {
            messages[0] = ChatMessage(role: "system", content: AppText.systemPrompt())
        }
    }
}

final class SearchOverlayView: NSView {
    let searchField = NSTextField(string: "")
    private let resultLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    var onSubmit: ((String) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func focus() {
        window?.makeFirstResponder(searchField)
    }

    func setResultText(_ text: String) {
        resultLabel.stringValue = text
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.995, green: 0.985, blue: 0.995, alpha: 0.98).cgColor
        layer?.cornerRadius = 14
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -7)

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 18)
        searchField.placeholderString = AppText.localized("搜索 PDF", "Search PDF")
        searchField.target = self
        searchField.action = #selector(submitSearch)

        resultLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        resultLabel.textColor = NSColor(red: 0.42, green: 0.42, blue: 0.47, alpha: 1)
        resultLabel.alignment = .right

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(red: 0.82, green: 0.72, blue: 0.98, alpha: 0.65).cgColor

        configureIconButton(previousButton, symbol: "chevron.up", action: #selector(previousResult))
        configureIconButton(nextButton, symbol: "chevron.down", action: #selector(nextResult))
        configureIconButton(closeButton, symbol: "xmark", action: #selector(closeSearch))

        for view in [searchField, resultLabel, separator, previousButton, nextButton, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: resultLabel.leadingAnchor, constant: -12),

            resultLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            resultLabel.widthAnchor.constraint(equalToConstant: 72),

            separator.leadingAnchor.constraint(equalTo: resultLabel.trailingAnchor, constant: 18),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 44),

            previousButton.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 18),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 36),
            previousButton.heightAnchor.constraint(equalToConstant: 36),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 14),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36),

            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 18),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.target = self
        button.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor(red: 0.44, green: 0.44, blue: 0.48, alpha: 1)
    }

    @objc private func submitSearch() {
        onSubmit?(searchField.stringValue)
    }

    @objc private func previousResult() {
        onPrevious?()
    }

    @objc private func nextResult() {
        onNext?()
    }

    @objc private func closeSearch() {
        onClose?()
    }
}

final class ReaderWindowController: NSWindowController, NSWindowDelegate, PDFViewDelegate, NSTextFieldDelegate, WKScriptMessageHandler {
    private static let preferredAIWidthDefaultsKey = "preferredAIWidth"

    private var pdfView: EdgePagingPDFView!
    private var webView: WKWebView!
    private let contentArea = NSView()
    private let pdfContainer = ClippingView()
    private let aiPanel = AIChatPanel()
    private let aiHandleButton = SideHandleButton(title: "", target: nil, action: nil)
    private let resizeHandle = ResizeHandleView()
    private let titleLabel = NSTextField(labelWithString: "Leaf Reader")
    private let coverImageView = NSImageView()
    private let pageLabel = NSTextField(labelWithString: AppText.noPDF)
    private let zoomField = NSTextField(string: "100%")
    private let searchOverlay = SearchOverlayView()
    private var fullScreenButton: NSButton!
    private var coverButton: NSButton!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var searchButton: NSButton!
    private var currentFileURL: URL?
    private var currentFileMD5: String?
    private var currentDocumentKind: ReaderDocumentKind = .pdf
    private var currentWebPlainText = ""
    private var currentWebSelectedText = ""
    private var lastPageIndex: Int?
    private var searchResults: [PDFSelection] = []
    private var searchResultIndex = 0
    private var lastSearchQuery = ""
    private var highlightedSelectionKeys = Set<String>()
    private var didRegisterSelectionObserver = false
    private var isRestoringSession = false
    private var isEditingZoomField = false
    private var isAIPanelCollapsed = true
    private var preferredAIWidth: CGFloat = ReaderWindowController.loadPreferredAIWidth()
    private var pendingAICollapseWorkItem: DispatchWorkItem?
    private var aiSettingsPanel: NSWindow?
    private weak var aiSettingsModelPopup: NSPopUpButton?
    private weak var aiSettingsLanguagePopup: NSPopUpButton?
    private weak var aiSettingsSecureKeyField: NSSecureTextField?
    private weak var aiSettingsPlainKeyField: NSTextField?
    private var aiHandleLeadingConstraint: NSLayoutConstraint!
    private var aiPanelWidthConstraint: NSLayoutConstraint!
    private var keyDownMonitor: Any?

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Leaf Reader"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)
        window.setFrameAutosaveName("LeafReaderClean")
        window.center()

        self.init(window: window)
        window.delegate = self
        buildUI()
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
        NotificationCenter.default.removeObserver(self)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        installKeyboardPagingMonitor()

        pdfView = EdgePagingPDFView()
        pdfView.wantsLayer = true
        pdfView.layer?.masksToBounds = true
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayBox = .cropBox
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1)
        pdfView.delegate = self
        pdfView.onScrollPastPageEdge = { [weak self] direction in
            self?.turnPageFromScroll(direction)
        }

        let webConfiguration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "selectionChanged")
        userContentController.addUserScript(WKUserScript(
            source: """
            (() => {
              const sendSelection = () => {
                window.webkit.messageHandlers.selectionChanged.postMessage(String(window.getSelection() || ""));
              };
              document.addEventListener("selectionchange", () => setTimeout(sendSelection, 0));
              document.addEventListener("mouseup", sendSelection);
              document.addEventListener("keyup", sendSelection);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        webConfiguration.userContentController = userContentController
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor
        webView.isHidden = true

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)

        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = NSColor(red: 0.965, green: 0.972, blue: 0.98, alpha: 1).cgColor

        let toolbar = NSView()
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        toolbar.layer?.borderColor = NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1).cgColor
        toolbar.layer?.borderWidth = 1

        let bottomBar = NSView()
        bottomBar.wantsLayer = true
        bottomBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        bottomBar.layer?.borderColor = NSColor(red: 0.88, green: 0.9, blue: 0.93, alpha: 1).cgColor
        bottomBar.layer?.borderWidth = 1

        let openButton = iconButton(symbol: "folder", action: #selector(openPDF))
        let settingsButton = iconButton(symbol: "gearshape", action: #selector(openAISettings))
        titleLabel.font = NSFont.systemFont(ofSize: 15)
        titleLabel.textColor = NSColor(red: 0.1, green: 0.11, blue: 0.14, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.toolTip = AppText.localized("从当前目录选择 PDF", "Choose PDF from Current Folder")
        titleLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openPDFInCurrentDirectory)))

        coverImageView.imageScaling = .scaleProportionallyUpOrDown
        coverImageView.wantsLayer = true
        coverImageView.layer?.backgroundColor = NSColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1).cgColor
        coverImageView.layer?.borderColor = NSColor(red: 0.78, green: 0.81, blue: 0.86, alpha: 1).cgColor
        coverImageView.layer?.borderWidth = 1
        coverImageView.layer?.cornerRadius = 3
        coverImageView.layer?.masksToBounds = true
        coverImageView.isHidden = true
        coverImageView.toolTip = AppText.localized("从当前目录选择 PDF", "Choose PDF from Current Folder")
        coverImageView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openPDFInCurrentDirectory)))

        let zoomOut = plainButton(title: "-", action: #selector(zoomOut))
        let zoomIn = plainButton(title: "+", action: #selector(zoomIn))
        let zoomGroup = NSView()
        zoomGroup.wantsLayer = true
        zoomGroup.layer?.backgroundColor = NSColor.white.cgColor
        zoomGroup.layer?.borderColor = NSColor(red: 0.84, green: 0.86, blue: 0.9, alpha: 1).cgColor
        zoomGroup.layer?.borderWidth = 1
        zoomGroup.layer?.cornerRadius = 7

        zoomField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        zoomField.alignment = .center
        zoomField.isBordered = false
        zoomField.drawsBackground = false
        zoomField.focusRingType = .none
        zoomField.delegate = self
        zoomField.target = self
        zoomField.action = #selector(applyZoomFromField)

        let leftDivider = divider()
        let rightDivider = divider()
        for view in [zoomOut, leftDivider, zoomField, rightDivider, zoomIn] {
            view.translatesAutoresizingMaskIntoConstraints = false
            zoomGroup.addSubview(view)
        }

        pageLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        pageLabel.alignment = .center
        searchButton = iconButton(symbol: "magnifyingglass", action: #selector(showSearchOverlay))
        searchButton.toolTip = AppText.localized("搜索 PDF", "Search PDF")

        fullScreenButton = capsuleButton(title: AppText.fullScreen, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(toggleFullScreen))
        coverButton = capsuleButton(title: AppText.cover, symbol: "book.closed", action: #selector(goToCover))
        prevButton = capsuleButton(title: AppText.prev, symbol: "chevron.left", action: #selector(prevPage))
        nextButton = capsuleButton(title: AppText.next, symbol: "chevron.right", action: #selector(nextPage), imageOnRight: true)

        pdfContainer.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(pdfContainer)
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.addSubview(pdfView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        pdfContainer.addSubview(webView)

        for view in [aiPanel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentArea.addSubview(view)
        }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(resizeHandle, positioned: .above, relativeTo: aiPanel)
        aiPanelWidthConstraint = aiPanel.widthAnchor.constraint(equalToConstant: 1)
        aiPanelWidthConstraint.priority = .required
        aiPanelWidthConstraint.isActive = true

        for view in [toolbar, contentArea, bottomBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        aiHandleButton.target = self
        aiHandleButton.action = #selector(toggleAIPanel)
        aiHandleButton.isBordered = false
        aiHandleButton.wantsLayer = true
        aiHandleButton.layer?.shadowColor = NSColor.black.cgColor
        aiHandleButton.layer?.shadowOpacity = 0.18
        aiHandleButton.layer?.shadowRadius = 12
        aiHandleButton.layer?.shadowOffset = CGSize(width: -2, height: -2)
        aiHandleButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(aiHandleButton, positioned: .above, relativeTo: contentArea)
        aiHandleLeadingConstraint = aiHandleButton.leadingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -SideHandleButton.handleWidth)

        resizeHandle.onDragDeltaX = { [weak self] deltaX in
            self?.resizeAIPanel(deltaX: deltaX)
        }
        aiPanel.onAskSelectedText = { [weak self] text in
            guard let self else { return nil }
            let context = self.contextForCurrentSelection(selectedText: text)
            if self.currentDocumentKind == .pdf {
                self.markSelectionIfWord(self.pdfView.currentSelection, text: text)
            }
            return context
        }
        aiPanel.onSettingsRequired = { [weak self] in
            self?.openAISettings()
        }

        searchOverlay.isHidden = true
        searchOverlay.onSubmit = { [weak self] query in
            self?.performSearch(query)
        }
        searchOverlay.onPrevious = { [weak self] in
            self?.goToPreviousSearchResult()
        }
        searchOverlay.onNext = { [weak self] in
            self?.goToNextSearchResult()
        }
        searchOverlay.onClose = { [weak self] in
            self?.hideSearchOverlay()
        }
        searchOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchOverlay, positioned: .above, relativeTo: contentArea)

        for view in [openButton, titleLabel, coverImageView, zoomGroup, pageLabel, searchButton!, fullScreenButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }

        for view in [settingsButton, coverButton!, prevButton!, nextButton!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(view)
        }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 58),

            bottomBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 52),

            contentArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            pdfContainer.topAnchor.constraint(equalTo: contentArea.topAnchor),
            pdfContainer.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            pdfContainer.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            pdfContainer.trailingAnchor.constraint(equalTo: aiPanel.leadingAnchor),

            pdfView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            webView.topAnchor.constraint(equalTo: pdfContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: pdfContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: pdfContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: pdfContainer.bottomAnchor),

            aiPanel.topAnchor.constraint(equalTo: contentArea.topAnchor),
            aiPanel.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            aiPanel.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),

            resizeHandle.topAnchor.constraint(equalTo: contentArea.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            resizeHandle.centerXAnchor.constraint(equalTo: aiPanel.leadingAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 6),

            aiHandleButton.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 90),
            aiHandleLeadingConstraint,
            aiHandleButton.widthAnchor.constraint(equalToConstant: SideHandleButton.handleWidth),
            aiHandleButton.heightAnchor.constraint(equalToConstant: SideHandleButton.handleHeight),

            openButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 112),
            openButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 24),
            openButton.heightAnchor.constraint(equalToConstant: 24),

            settingsButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 18),
            settingsButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 24),
            settingsButton.heightAnchor.constraint(equalToConstant: 24),

            coverImageView.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 28),
            coverImageView.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 28),
            coverImageView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 230),

            zoomGroup.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 24),
            zoomGroup.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomGroup.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: -80),
            zoomGroup.widthAnchor.constraint(equalToConstant: 132),
            zoomGroup.heightAnchor.constraint(equalToConstant: 32),

            zoomOut.leadingAnchor.constraint(equalTo: zoomGroup.leadingAnchor),
            zoomOut.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomOut.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomOut.widthAnchor.constraint(equalToConstant: 40),
            leftDivider.leadingAnchor.constraint(equalTo: zoomOut.trailingAnchor),
            leftDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            leftDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            leftDivider.widthAnchor.constraint(equalToConstant: 1),
            zoomField.leadingAnchor.constraint(equalTo: leftDivider.trailingAnchor),
            zoomField.centerYAnchor.constraint(equalTo: zoomGroup.centerYAnchor),
            zoomField.widthAnchor.constraint(equalToConstant: 50),
            rightDivider.leadingAnchor.constraint(equalTo: zoomField.trailingAnchor),
            rightDivider.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            rightDivider.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: 1),
            zoomIn.leadingAnchor.constraint(equalTo: rightDivider.trailingAnchor),
            zoomIn.topAnchor.constraint(equalTo: zoomGroup.topAnchor),
            zoomIn.bottomAnchor.constraint(equalTo: zoomGroup.bottomAnchor),
            zoomIn.trailingAnchor.constraint(equalTo: zoomGroup.trailingAnchor),

            pageLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor, constant: 130),
            pageLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: 140),

            searchButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 6),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 28),
            searchButton.heightAnchor.constraint(equalToConstant: 28),

            fullScreenButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            fullScreenButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 30),

            searchOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            searchOverlay.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            searchOverlay.widthAnchor.constraint(equalToConstant: 560),
            searchOverlay.heightAnchor.constraint(equalToConstant: 70),

            coverButton.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -12),
            coverButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            coverButton.widthAnchor.constraint(equalToConstant: 100),
            coverButton.heightAnchor.constraint(equalToConstant: 30),

            prevButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor, constant: -48),
            prevButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 84),
            prevButton.heightAnchor.constraint(equalToConstant: 30),
            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 12),
            nextButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 84),
            nextButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.setAIPanelCollapsed(true, animated: false)
        }
        restoreSession()
    }

    private func iconButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        return button
    }

    private func plainButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        return button
    }

    private func capsuleButton(title: String, symbol: String, action: Selector, imageOnRight: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: 13)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = imageOnRight ? .imageRight : .imageLeft
        return button
    }

    private func divider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1).cgColor
        return view
    }

    private func refreshLanguageUI() {
        aiPanel.refreshLanguage()
        fullScreenButton.title = window?.styleMask.contains(.fullScreen) == true ? AppText.windowed : AppText.fullScreen
        coverButton.title = AppText.cover
        prevButton.title = AppText.prev
        nextButton.title = AppText.next
        if pdfView.document == nil {
            pageLabel.stringValue = AppText.noPDF
        }
        fullScreenButton.image = NSImage(
            systemSymbolName: window?.styleMask.contains(.fullScreen) == true ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
        coverButton.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: AppText.cover)
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: AppText.prev)
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: AppText.next)
    }

    @objc private func openAISettings() {
        let selectedModel = AISettingsStore.selectedModel
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false

        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = 0.18
        content.layer?.shadowRadius = 24
        content.layer?.shadowOffset = CGSize(width: 0, height: -8)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content

        let titleLabel = NSTextField(labelWithString: AppText.settings)
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "", target: self, action: #selector(cancelAISettings(_:)))
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: AppText.close)
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let modelHelpLabel = NSTextField(labelWithString: AppText.modelHelp)
        modelHelpLabel.font = NSFont.systemFont(ofSize: 16)
        modelHelpLabel.textColor = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        modelHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        let keyHelpLabel = NSTextField(labelWithString: AppText.keyHelp)
        keyHelpLabel.font = NSFont.systemFont(ofSize: 16)
        keyHelpLabel.textColor = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        keyHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        let languageHelpLabel = NSTextField(labelWithString: AppText.languageHelp)
        languageHelpLabel.font = NSFont.systemFont(ofSize: 16)
        languageHelpLabel.textColor = NSColor(red: 0.47, green: 0.50, blue: 0.58, alpha: 1)
        languageHelpLabel.translatesAutoresizingMaskIntoConstraints = false

        let modelLabel = NSTextField(labelWithString: AppText.model)
        modelLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.controlSize = .large
        modelPopup.font = NSFont.systemFont(ofSize: 18)
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        for model in AISettingsStore.models {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.id
        }
        if let index = AISettingsStore.models.firstIndex(where: { $0.id == selectedModel.id }) {
            modelPopup.selectItem(at: index)
        }

        let languageLabel = NSTextField(labelWithString: AppText.language)
        languageLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.controlSize = .large
        languagePopup.font = NSFont.systemFont(ofSize: 18)
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        for language in AppText.Language.allCases {
            languagePopup.addItem(withTitle: language.title)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        if let index = AppText.Language.allCases.firstIndex(of: AppText.selectedLanguage) {
            languagePopup.selectItem(at: index)
        }

        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        let keyField = APIKeySecureTextField(string: AISettingsStore.apiKey(for: selectedModel))
        keyField.placeholderString = AppText.apiKeyPlaceholder
        keyField.controlSize = .regular
        keyField.font = NSFont.systemFont(ofSize: 22)
        keyField.isBordered = true
        keyField.drawsBackground = true
        keyField.isEditable = true
        keyField.isSelectable = true
        keyField.isEnabled = true
        keyField.translatesAutoresizingMaskIntoConstraints = false

        let plainKeyField = APIKeyTextField(string: AISettingsStore.apiKey(for: selectedModel))
        plainKeyField.placeholderString = AppText.apiKeyPlaceholder
        plainKeyField.controlSize = .regular
        plainKeyField.font = NSFont.systemFont(ofSize: 22)
        plainKeyField.isBordered = true
        plainKeyField.drawsBackground = true
        plainKeyField.isEditable = true
        plainKeyField.isSelectable = true
        plainKeyField.isEnabled = true
        plainKeyField.isHidden = true
        plainKeyField.translatesAutoresizingMaskIntoConstraints = false

        let eyeButton = NSButton(title: "", target: self, action: #selector(toggleAISettingsAPIKeyVisibility(_:)))
        eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: AppText.showAPIKey)
        eyeButton.isBordered = false
        eyeButton.contentTintColor = NSColor(red: 0.36, green: 0.39, blue: 0.48, alpha: 1)
        eyeButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: AppText.cancel, target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let saveButton = NSButton(title: AppText.confirm, target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .large
        saveButton.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        modelPopup.target = self
        modelPopup.action = #selector(aiSettingsModelChanged(_:))
        modelPopup.identifier = NSUserInterfaceItemIdentifier("modelPopup")
        languagePopup.identifier = NSUserInterfaceItemIdentifier("languagePopup")
        keyField.identifier = NSUserInterfaceItemIdentifier("keyField")
        plainKeyField.identifier = NSUserInterfaceItemIdentifier("plainKeyField")
        for view in [titleLabel, closeButton, modelLabel, modelPopup, modelHelpLabel, languageLabel, languagePopup, languageHelpLabel, keyLabel, keyField, plainKeyField, eyeButton, keyHelpLabel, cancelButton, saveButton] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 48),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -48),

            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            modelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 66),
            modelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelPopup.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 14),
            modelPopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelPopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            modelPopup.heightAnchor.constraint(equalToConstant: 54),
            modelHelpLabel.topAnchor.constraint(equalTo: modelPopup.bottomAnchor, constant: 12),
            modelHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            modelHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            keyLabel.topAnchor.constraint(equalTo: modelHelpLabel.bottomAnchor, constant: 30),
            keyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 10),
            keyField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyField.trailingAnchor.constraint(equalTo: eyeButton.leadingAnchor, constant: -10),
            keyField.heightAnchor.constraint(equalToConstant: 46),
            plainKeyField.topAnchor.constraint(equalTo: keyField.topAnchor),
            plainKeyField.leadingAnchor.constraint(equalTo: keyField.leadingAnchor),
            plainKeyField.trailingAnchor.constraint(equalTo: keyField.trailingAnchor),
            plainKeyField.heightAnchor.constraint(equalTo: keyField.heightAnchor),
            eyeButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            eyeButton.centerYAnchor.constraint(equalTo: keyField.centerYAnchor),
            eyeButton.widthAnchor.constraint(equalToConstant: 28),
            eyeButton.heightAnchor.constraint(equalToConstant: 28),
            keyHelpLabel.topAnchor.constraint(equalTo: keyField.bottomAnchor, constant: 10),
            keyHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            keyHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            languageLabel.topAnchor.constraint(equalTo: keyHelpLabel.bottomAnchor, constant: 30),
            languageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languagePopup.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 14),
            languagePopup.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languagePopup.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            languagePopup.heightAnchor.constraint(equalToConstant: 54),
            languageHelpLabel.topAnchor.constraint(equalTo: languagePopup.bottomAnchor, constant: 12),
            languageHelpLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            languageHelpLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            saveButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -36),
            saveButton.widthAnchor.constraint(equalToConstant: 118),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 118),
            cancelButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        cancelButton.target = self
        cancelButton.action = #selector(cancelAISettings(_:))
        closeButton.target = self
        closeButton.action = #selector(cancelAISettings(_:))
        saveButton.target = self
        saveButton.action = #selector(saveAISettings(_:))
        saveButton.identifier = NSUserInterfaceItemIdentifier("saveAISettings")

        aiSettingsPanel = panel
        aiSettingsModelPopup = modelPopup
        aiSettingsLanguagePopup = languagePopup
        aiSettingsSecureKeyField = keyField
        aiSettingsPlainKeyField = plainKeyField

        window?.beginSheet(panel) { _ in }
        DispatchQueue.main.async {
            panel.makeKey()
            panel.makeFirstResponder(keyField)
        }
    }

    @objc private func saveAISettings(_ sender: NSButton) {
        guard
            let panel = aiSettingsPanel,
            let modelPopup = aiSettingsModelPopup,
            let keyField = currentAISettingsKeyField()
        else { return }

        let modelID = modelPopup.selectedItem?.representedObject as? String ?? AISettingsStore.selectedModel.id
        if let rawLanguage = aiSettingsLanguagePopup?.selectedItem?.representedObject as? String,
           let language = AppText.Language(rawValue: rawLanguage) {
            AppText.selectedLanguage = language
        }
        AISettingsStore.save(modelID: modelID, apiKey: keyField.stringValue)
        refreshLanguageUI()
        panel.sheetParent?.endSheet(panel)
    }

    @objc private func cancelAISettings(_ sender: NSButton) {
        guard let panel = aiSettingsPanel else { return }
        panel.sheetParent?.endSheet(panel)
    }

    @objc private func aiSettingsModelChanged(_ sender: NSPopUpButton) {
        guard
            let modelID = sender.selectedItem?.representedObject as? String,
            let model = AISettingsStore.models.first(where: { $0.id == modelID })
        else { return }

        let key = AISettingsStore.apiKey(for: model)
        aiSettingsSecureKeyField?.stringValue = key
        aiSettingsPlainKeyField?.stringValue = key
    }

    @objc private func toggleAISettingsAPIKeyVisibility(_ sender: NSButton) {
        guard let secureField = aiSettingsSecureKeyField, let plainField = aiSettingsPlainKeyField else { return }
        if plainField.isHidden {
            plainField.stringValue = secureField.stringValue
            plainField.isHidden = false
            secureField.isHidden = true
            sender.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: AppText.hideAPIKey)
            window?.makeFirstResponder(plainField)
        } else {
            secureField.stringValue = plainField.stringValue
            secureField.isHidden = false
            plainField.isHidden = true
            sender.image = NSImage(systemSymbolName: "eye", accessibilityDescription: AppText.showAPIKey)
            window?.makeFirstResponder(secureField)
        }
    }

    private func currentAISettingsKeyField() -> NSTextField? {
        if let plainField = aiSettingsPlainKeyField, !plainField.isHidden {
            return plainField
        }
        return aiSettingsSecureKeyField
    }

    private func findKeyField(in view: NSView) -> NSTextField? {
        if let keyField = view as? NSTextField,
           keyField.identifier?.rawValue == "keyField" || keyField.identifier?.rawValue == "plainKeyField" {
            return keyField
        }
        for subview in view.subviews {
            if let keyField = findKeyField(in: subview) {
                return keyField
            }
        }
        return nil
    }

    @objc private func toggleAIPanel() {
        cancelScheduledAICollapse()
        setAIPanelCollapsed(!isAIPanelCollapsed, animated: true)
    }

    private func scheduleAICollapse() {
        cancelScheduledAICollapse()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setAIPanelCollapsed(true, animated: true)
        }
        pendingAICollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: workItem)
    }

    private func cancelScheduledAICollapse() {
        pendingAICollapseWorkItem?.cancel()
        pendingAICollapseWorkItem = nil
    }

    private func setAIPanelCollapsed(_ collapsed: Bool, animated: Bool) {
        if collapsed, aiPanel.frame.width > 80 {
            preferredAIWidth = clampedAIWidth(aiPanel.frame.width)
            savePreferredAIWidth()
        } else {
            preferredAIWidth = clampedAIWidth(preferredAIWidth)
            savePreferredAIWidth()
        }
        isAIPanelCollapsed = collapsed
        aiPanel.isHidden = false
        if collapsed {
            aiPanel.setContentVisible(false)
        }
        aiHandleButton.collapsedStyle = collapsed
        resizeHandle.isHidden = collapsed

        let targetAIWidth: CGFloat = collapsed ? 1 : clampedAIWidth(preferredAIWidth)
        let update = {
            self.aiPanelWidthConstraint.constant = targetAIWidth
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.refreshPDFLayoutAfterPanelChange()
            self.updateAIHandlePosition()
            if !collapsed {
                self.aiPanel.setContentVisible(true)
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.07
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                update()
            }
        } else {
            update()
        }
    }

    private func clampedAIWidth(_ width: CGFloat) -> CGFloat {
        let maxWidth = max(300, contentArea.bounds.width - 320)
        return min(max(width, 300), min(520, maxWidth))
    }

    private static func loadPreferredAIWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: preferredAIWidthDefaultsKey)
        guard width > 0 else { return 420 }
        return CGFloat(width)
    }

    private func savePreferredAIWidth() {
        UserDefaults.standard.set(Double(preferredAIWidth), forKey: Self.preferredAIWidthDefaultsKey)
    }

    private func updateAIHandlePosition() {
        let aiWidth = isAIPanelCollapsed ? 1 : aiPanelWidthConstraint.constant
        aiHandleLeadingConstraint.constant = isAIPanelCollapsed
            ? -SideHandleButton.handleWidth
            : -(aiWidth + SideHandleButton.handleWidth)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func refreshPDFLayoutAfterPanelChange() {
        pdfContainer.layoutSubtreeIfNeeded()
        pdfView.layoutSubtreeIfNeeded()
        pdfView.setNeedsDisplay(pdfView.bounds)
        pdfView.documentView?.setNeedsDisplay(pdfView.documentView?.bounds ?? .zero)
    }

    private func syncAIPanelLayoutAfterResize() {
        guard contentArea.bounds.width > 0 else { return }
        if isAIPanelCollapsed {
            aiPanelWidthConstraint.constant = 1
            aiPanel.setContentVisible(false)
            resizeHandle.isHidden = true
        } else {
            preferredAIWidth = clampedAIWidth(preferredAIWidth)
            aiPanelWidthConstraint.constant = preferredAIWidth
            savePreferredAIWidth()
            aiPanel.setContentVisible(true)
            resizeHandle.isHidden = false
        }
        contentArea.layoutSubtreeIfNeeded()
        refreshPDFLayoutAfterPanelChange()
        updateAIHandlePosition()
    }

    private func resizeAIPanel(deltaX: CGFloat) {
        guard !isAIPanelCollapsed else { return }
        preferredAIWidth = clampedAIWidth(preferredAIWidth - deltaX)
        savePreferredAIWidth()
        aiPanelWidthConstraint.constant = preferredAIWidth
        contentArea.layoutSubtreeIfNeeded()
        refreshPDFLayoutAfterPanelChange()
        updateAIHandlePosition()
    }

    private func updateFullScreenButton() {
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        fullScreenButton.title = isFullScreen ? AppText.windowed : AppText.fullScreen
        fullScreenButton.image = NSImage(
            systemSymbolName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: fullScreenButton.title
        )
    }

    func windowDidResize(_ notification: Notification) {
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        updateFullScreenButton()
        syncAIPanelLayoutAfterResize()
    }

    @objc private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadDocument(url)
        }
    }

    private var supportedContentTypes: [UTType] {
        [.pdf] + ["epub", "docx"].compactMap { UTType(filenameExtension: $0) }
    }

    private func loadDocument(_ url: URL) {
        guard let kind = ReaderDocumentKind.kind(for: url) else { return }
        switch kind {
        case .pdf:
            loadPDF(url)
        case .epub, .docx:
            loadWebDocument(url, kind: kind)
        }
    }

    private func loadPDF(_ url: URL) {
        guard let document = PDFDocument(url: url) else { return }
        currentDocumentKind = .pdf
        pdfView.isHidden = false
        webView.isHidden = true
        pdfView.document = document
        currentFileURL = url
        currentFileMD5 = fileMD5(for: url)
        currentWebPlainText = ""
        currentWebSelectedText = ""
        highlightedSelectionKeys.removeAll()
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        updateCoverThumbnail(from: document)

        if !didRegisterSelectionObserver {
            didRegisterSelectionObserver = true
            NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)
        }

        restoreBookProgressOrGoHome()
        lastPageIndex = currentPageIndex()
        updatePageLabel()
        updateZoomLabel()
        saveSession()
    }

    private func loadWebDocument(_ url: URL, kind: ReaderDocumentKind) {
        do {
            let document = try WebDocumentLoader.load(url: url)
            currentDocumentKind = kind
            pdfView.isHidden = true
            webView.isHidden = false
            pdfView.document = nil
            currentFileURL = url
            currentFileMD5 = fileMD5(for: url)
            currentWebPlainText = document.plainText
            currentWebSelectedText = ""
            highlightedSelectionKeys.removeAll()
            searchResults.removeAll()
            searchResultIndex = 0
            lastSearchQuery = ""
            searchOverlay.setResultText("")
            aiPanel.setSelectedText("")
            titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
            coverImageView.image = NSImage(systemSymbolName: kind == .epub ? "book.closed" : "doc.text", accessibilityDescription: nil)
            coverImageView.isHidden = false
            pageLabel.stringValue = kind == .epub ? "EPUB" : "DOCX"
            zoomField.stringValue = "100%"
            webView.loadHTMLString(document.html, baseURL: document.baseURL)
            saveSession()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func updateCoverThumbnail(from document: PDFDocument) {
        guard let firstPage = document.page(at: 0) else {
            coverImageView.image = nil
            coverImageView.isHidden = true
            return
        }

        coverImageView.image = firstPage.thumbnail(of: CGSize(width: 56, height: 76), for: .cropBox)
        coverImageView.isHidden = false
    }

    func openDocument(_ url: URL) {
        loadDocument(url)
    }

    @objc private func openPDFInCurrentDirectory() {
        guard let url = currentFileURL else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            self?.loadDocument(selectedURL)
        }
    }

    @objc private func zoomIn() {
        guard currentDocumentKind == .pdf else { return }
        pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8)
        updateZoomLabel()
        saveSession()
    }

    @objc private func zoomOut() {
        guard currentDocumentKind == .pdf else { return }
        pdfView.scaleFactor = max(pdfView.scaleFactor * 0.8, 0.1)
        updateZoomLabel()
        saveSession()
    }

    @objc private func applyZoomFromField() {
        guard currentDocumentKind == .pdf else {
            zoomField.stringValue = "100%"
            return
        }
        let raw = zoomField.stringValue
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "％", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(raw), percent > 0 else {
            updateZoomLabel()
            return
        }
        pdfView.scaleFactor = min(max(percent, 10), 800) / 100
        updateZoomLabel()
        saveSession()
        window?.makeFirstResponder(currentDocumentKind == .pdf ? pdfView : webView)
    }

    @objc private func prevPage() {
        guard currentDocumentKind == .pdf else { return }
        pdfView.goToPreviousPage(nil)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    @objc private func nextPage() {
        guard currentDocumentKind == .pdf else { return }
        pdfView.goToNextPage(nil)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    @objc private func goToCover() {
        guard currentDocumentKind == .pdf else {
            webView.evaluateJavaScript("window.scrollTo({top:0, behavior:'smooth'});")
            return
        }
        guard let firstPage = pdfView.document?.page(at: 0) else { return }
        pdfView.go(to: firstPage)
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    @objc private func showSearchOverlay() {
        searchOverlay.isHidden = false
        window?.makeFirstResponder(searchOverlay.searchField)
    }

    private func hideSearchOverlay() {
        searchOverlay.isHidden = true
        searchResults.removeAll()
        searchResultIndex = 0
        lastSearchQuery = ""
        searchOverlay.setResultText("")
        pdfView.clearSelection()
        clearWebSearchSelection()
        window?.makeFirstResponder(pdfView)
    }

    private func performSearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults.removeAll()
            searchResultIndex = 0
            lastSearchQuery = ""
            searchOverlay.setResultText("")
            pdfView.clearSelection()
            clearWebSearchSelection()
            return
        }
        guard currentDocumentKind == .pdf else {
            performWebSearch(query, backwards: false)
            return
        }
        guard let document = pdfView.document else {
            searchOverlay.setResultText("0 / 0")
            return
        }

        if query != lastSearchQuery {
            searchResults = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            searchResultIndex = 0
            lastSearchQuery = query
        } else if !searchResults.isEmpty {
            searchResultIndex = (searchResultIndex + 1) % searchResults.count
        }

        showCurrentSearchResult()
    }

    private func goToPreviousSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: true)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchResultIndex = (searchResultIndex - 1 + searchResults.count) % searchResults.count
        showCurrentSearchResult()
    }

    private func goToNextSearchResult() {
        guard currentDocumentKind == .pdf else {
            performWebSearch(searchOverlay.searchField.stringValue, backwards: false)
            return
        }
        guard !searchResults.isEmpty else {
            performSearch(searchOverlay.searchField.stringValue)
            return
        }
        searchResultIndex = (searchResultIndex + 1) % searchResults.count
        showCurrentSearchResult()
    }

    private func showCurrentSearchResult() {
        guard !searchResults.isEmpty else {
            searchOverlay.setResultText("0 / 0")
            pdfView.clearSelection()
            return
        }

        let selection = searchResults[searchResultIndex]
        pdfView.setCurrentSelection(selection, animate: true)
        goToVisibleSearchSelection(selection)
        updatePageLabel()
        saveSession()
        searchOverlay.setResultText("\(searchResultIndex + 1) / \(searchResults.count)")
    }

    private func goToVisibleSearchSelection(_ selection: PDFSelection) {
        guard let page = selection.pages.first else {
            pdfView.go(to: selection)
            return
        }

        let selectionBounds = selection.bounds(for: page)
        guard !selectionBounds.isEmpty else {
            pdfView.go(to: selection)
            return
        }

        let pageBounds = page.bounds(for: pdfView.displayBox)
        let overlayClearance = searchOverlay.isHidden ? CGFloat(64) : CGFloat(150)
        let yOffset = overlayClearance / max(pdfView.scaleFactor, 0.1)
        let destinationY = min(pageBounds.maxY, selectionBounds.maxY + yOffset)
        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: max(pageBounds.minX, selectionBounds.minX), y: destinationY)
        )
        pdfView.go(to: destination)
    }

    private func performWebSearch(_ rawQuery: String, backwards: Bool) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchOverlay.setResultText("")
            clearWebSearchSelection()
            return
        }

        let escapedQuery = jsStringLiteral(query)
        let script = """
        (() => {
          const query = \(escapedQuery);
          const found = window.find(query, false, \(backwards ? "true" : "false"), true, false, true, false);
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            const rect = selection.getRangeAt(0).getBoundingClientRect();
            window.scrollBy({ top: rect.top - 160, behavior: 'smooth' });
          }
          return found;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            let found = result as? Bool ?? false
            self?.searchOverlay.setResultText(found ? AppText.localized("找到", "Found") : "0 / 0")
        }
    }

    private func clearWebSearchSelection() {
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges();")
    }

    private func jsStringLiteral(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }

    private func turnPageFromScroll(_ direction: EdgePagingPDFView.ScrollPageDirection) {
        guard currentDocumentKind == .pdf else { return }
        switch direction {
        case .previous:
            pdfView.goToPreviousPage(nil)
        case .next:
            pdfView.goToNextPage(nil)
        }
        scrollCurrentPageToTop()
        updatePageLabel()
        saveSession()
    }

    private func scrollCurrentPageToTop() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let page = self.pdfView.currentPage else { return }
            let bounds = page.bounds(for: self.pdfView.displayBox)
            let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
            self.pdfView.go(to: destination)
        }
    }

    @objc private func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    @objc private func pageChanged() {
        handlePDFPageChange()
    }

    private func handlePDFPageChange() {
        let newPageIndex = currentPageIndex()
        guard newPageIndex != lastPageIndex else {
            updatePageLabel()
            saveSession()
            return
        }
        lastPageIndex = newPageIndex
        updatePageLabel()
        saveSession()
    }

    private func hideAIPanelForPageTurn() {
        cancelScheduledAICollapse()
        aiPanel.setSelectedText("")
        setAIPanelCollapsed(true, animated: true)
    }

    @objc private func selectionChanged() {
        guard currentDocumentKind == .pdf else { return }
        let selection = pdfView.currentSelection
        let text = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(selectedText)
        if selectedText.isEmpty {
            scheduleAICollapse()
        } else {
            cancelScheduledAICollapse()
            setAIPanelCollapsed(false, animated: true)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "selectionChanged" else { return }
        let text = (message.body as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        currentWebSelectedText = text.count > 1 ? text : ""
        aiPanel.setSelectedText(currentWebSelectedText)
        if currentWebSelectedText.isEmpty {
            scheduleAICollapse()
        } else {
            cancelScheduledAICollapse()
            setAIPanelCollapsed(false, animated: true)
        }
    }

    private func markSelectionIfWord(_ selection: PDFSelection?, text: String) {
        guard shouldPersistHighlight(for: text), let selection = selection else { return }

        let lineSelections = selection.selectionsByLine()
        let selections = lineSelections.isEmpty ? [selection] : lineSelections
        for lineSelection in selections {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page).insetBy(dx: -1.5, dy: -1)
                guard bounds.width > 0, bounds.height > 0 else { continue }

                let pageIndex = pdfView.document?.index(for: page) ?? -1
                let key = "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
                guard !highlightedSelectionKeys.contains(key) else { continue }
                highlightedSelectionKeys.insert(key)

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = NSColor.systemYellow.withAlphaComponent(0.68)
                page.addAnnotation(annotation)
            }
        }
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    private func contextForCurrentSelection(selectedText: String) -> String {
        let normalizedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSelection.isEmpty else { return "" }

        guard currentDocumentKind == .pdf else {
            return sentenceContext(containing: normalizedSelection, in: currentWebPlainText)
                ?? characterWindowContext(containing: normalizedSelection, in: currentWebPlainText, radius: 80)
                ?? ""
        }

        if let selection = pdfView.currentSelection,
           let page = selection.pages.first {
            let pageText = page.string ?? ""
            if let context = sentenceContext(containing: normalizedSelection, in: pageText) {
                return context
            }

            let bounds = selection.bounds(for: page)
            let expandedBounds = bounds.insetBy(dx: -120, dy: -36)
            if let nearbyText = page.selection(for: expandedBounds)?.string,
               let context = sentenceContext(containing: normalizedSelection, in: nearbyText) ?? characterWindowContext(containing: normalizedSelection, in: nearbyText, radius: 20) {
                return context
            }
        }

        let currentPageText = pdfView.currentPage?.string ?? ""
        return characterWindowContext(containing: normalizedSelection, in: currentPageText, radius: 20) ?? ""
    }

    private func sentenceContext(containing selectedText: String, in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let sentenceStart = normalizedText[..<range.lowerBound].lastIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.startIndex
        let sentenceEnd = normalizedText[range.upperBound...].firstIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.endIndex
        let sentence = normalizeWhitespace(String(normalizedText[sentenceStart..<sentenceEnd]))
        guard sentence.count > normalizedSelection.count else { return nil }
        return sentence
    }

    private func characterWindowContext(containing selectedText: String, in text: String, radius: Int) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let prefixStart = normalizedText.index(range.lowerBound, offsetBy: -radius, limitedBy: normalizedText.startIndex) ?? normalizedText.startIndex
        let suffixEnd = normalizedText.index(range.upperBound, offsetBy: radius, limitedBy: normalizedText.endIndex) ?? normalizedText.endIndex
        return normalizeWhitespace(String(normalizedText[prefixStart..<suffixEnd]))
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldPersistHighlight(for text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 40 else { return false }
        guard normalized.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        return normalized.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    func pdfViewWillChangeScaleFactor(_ sender: PDFView) {
        updateZoomLabel()
    }

    func pdfViewPageChanged(_ sender: PDFView) {
        handlePDFPageChange()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = true
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if obj.object as? NSTextField === zoomField {
            isEditingZoomField = false
            updateZoomLabel()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === zoomField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            applyZoomFromField()
            return true
        }
        return false
    }

    private func updateZoomLabel() {
        if isEditingZoomField { return }
        guard currentDocumentKind == .pdf else {
            zoomField.stringValue = "100%"
            return
        }
        zoomField.stringValue = "\(Int(round(pdfView.scaleFactor * 100)))%"
    }

    private func updatePageLabel() {
        guard currentDocumentKind == .pdf else {
            pageLabel.stringValue = currentDocumentKind == .epub ? "EPUB" : "DOCX"
            return
        }
        guard let document = pdfView.document else {
            pageLabel.stringValue = AppText.noPDF
            return
        }
        guard let page = pdfView.currentPage else {
            pageLabel.stringValue = "1  /  \(document.pageCount)"
            return
        }
        pageLabel.stringValue = "\(document.index(for: page) + 1)  /  \(document.pageCount)"
    }

    private func currentPageIndex() -> Int? {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return nil }
        return document.index(for: page)
    }

    private func fileMD5(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func bookSessionKey(_ suffix: String) -> String? {
        guard let md5 = currentFileMD5 else { return nil }
        return "bookSession.\(md5).\(suffix)"
    }

    private func restoreBookProgressOrGoHome() {
        guard let document = pdfView.document else { return }
        guard
            let pageKey = bookSessionKey("pageIndex"),
            let scaleKey = bookSessionKey("scale"),
            UserDefaults.standard.object(forKey: pageKey) != nil
        else {
            if let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
            }
            pdfView.autoScales = true
            return
        }

        let pageIndex = UserDefaults.standard.integer(forKey: pageKey)
        if pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        } else if let firstPage = document.page(at: 0) {
            pdfView.go(to: firstPage)
        }

        let scale = UserDefaults.standard.double(forKey: scaleKey)
        if scale >= 0.1, scale <= 8 {
            pdfView.scaleFactor = scale
        }
    }

    private func saveSession() {
        if isRestoringSession { return }
        guard let url = currentFileURL else { return }
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope)) ?? Data()
        UserDefaults.standard.set(bookmark, forKey: "lastPDFBookmark")
        guard currentDocumentKind == .pdf else { return }
        let pageIndex = pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) ?? 0
        if let pageKey = bookSessionKey("pageIndex"), let scaleKey = bookSessionKey("scale") {
            UserDefaults.standard.set(pageIndex, forKey: pageKey)
            UserDefaults.standard.set(pdfView.scaleFactor, forKey: scaleKey)
        }
    }

    private func restoreSession() {
        guard let bookmark = UserDefaults.standard.data(forKey: "lastPDFBookmark"), !bookmark.isEmpty else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale else { return }

        isRestoringSession = true
        loadDocument(url)
        isRestoringSession = false
        updatePageLabel()
        updateZoomLabel()
        saveSession()
    }

    private func installKeyboardPagingMonitor() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.window else { return event }
            guard self.handlePageKey(event) else { return event }
            return nil
        }
    }

    private func handlePageKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            showSearchOverlay()
            return true
        }

        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }
        guard !isEditingTextInput else { return false }

        switch event.keyCode {
        case 123:
            prevPage()
            return true
        case 124:
            nextPage()
            return true
        default:
            return false
        }
    }

    private var isEditingTextInput: Bool {
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if !handlePageKey(event) {
            super.keyDown(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ReaderWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = ReaderWindowController()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        controller.window?.makeKeyAndOrderFront(nil)
        controller.openDocument(URL(fileURLWithPath: filename))
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

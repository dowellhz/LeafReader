import Cocoa
import CoreText

enum ReadingNotePDFExporter {
    enum ExportError: LocalizedError {
        case htmlConversionFailed
        case contextCreationFailed
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .htmlConversionFailed:
                return AppText.localized("无法生成 PDF 内容", "Could not build PDF content")
            case .contextCreationFailed:
                return AppText.localized("无法创建 PDF 文件", "Could not create the PDF file")
            case .emptyDocument:
                return AppText.localized("没有可导出的 PDF 内容", "No PDF content to export")
            }
        }
    }

    static func data(html: String) throws -> Data {
        guard let htmlData = html.data(using: .utf8) else {
            throw ExportError.htmlConversionFailed
        }
        let attributed = try NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        guard attributed.length > 0 else {
            throw ExportError.emptyDocument
        }
        return try renderPDF(attributed)
    }

    private static func renderPDF(_ attributed: NSAttributedString) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw ExportError.contextCreationFailed
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.contextCreationFailed
        }

        let margin: CGFloat = 54
        let contentRect = mediaBox.insetBy(dx: margin, dy: margin)
        let path = CGMutablePath()
        path.addRect(contentRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var range = CFRange(location: 0, length: 0)

        while range.location < attributed.length {
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)

            context.endPDFPage()

            guard visible.length > 0 else { break }
            range.location += visible.length
        }

        context.closePDF()
        return output as Data
    }
}

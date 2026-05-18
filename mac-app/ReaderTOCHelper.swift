import Foundation
import PDFKit

struct ReaderTOCHelper {
    struct PDFTOCDestination {
        let pageIndex: Int
        let point: NSPoint
    }

    struct PDFTOC {
        let items: [ReaderTOCItem]
        let destinations: [String: PDFTOCDestination]
    }

    static func pdfTOCItems(from document: PDFDocument, displayBox: PDFDisplayBox) -> PDFTOC {
        var destinations: [String: PDFTOCDestination] = [:]
        guard let root = document.outlineRoot else {
            return pdfPageTOCItems(from: document, displayBox: displayBox)
        }
        var items: [ReaderTOCItem] = []

        func walk(_ outline: PDFOutline, level: Int) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                if let destination = pdfDestination(for: child),
                   let page = destination.page {
                    let pageIndex = document.index(for: page)
                    guard pageIndex != NSNotFound else { continue }
                    let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = "pdf-toc-\(items.count)"
                    destinations[id] = PDFTOCDestination(pageIndex: pageIndex, point: destination.point)
                    items.append(ReaderTOCItem(
                        title: title?.isEmpty == false ? title! : AppText.localized("未命名目录", "Untitled"),
                        href: id,
                        level: min(level, 4)
                    ))
                }
                walk(child, level: level + 1)
            }
        }

        walk(root, level: 0)
        if items.isEmpty {
            return pdfPageTOCItems(from: document, displayBox: displayBox)
        }
        return PDFTOC(items: items, destinations: destinations)
    }

    static func webJumpScript(for item: ReaderTOCItem) -> String {
        return """
        (() => {
          const href = \(jsStringLiteral(item.href));
          const title = \(jsStringLiteral(item.title.prefix(16).description));
          const fragment = href.includes('#') ? href.split('#').pop() : (href.startsWith('#') ? href.slice(1) : '');
          if (fragment) {
            const byID = document.getElementById(fragment);
            if (byID) {
              byID.scrollIntoView({behavior:'smooth', block:'start'});
              return;
            }
          }
          const path = href.split('#')[0];
          let target = null;
          if (path) {
            target = Array.from(document.querySelectorAll('section.reader-section[data-leaf-href]')).find((section) => {
              const value = section.dataset.leafHref || '';
              return value === path || value.endsWith('/' + path) || path.endsWith('/' + value);
            });
          }
          if (!target) {
            target = Array.from(document.querySelectorAll('[id]')).find(el => el.id && el.id.includes(title));
          }
          if (target) target.scrollIntoView({behavior:'smooth', block:'start'});
        })();
        """
    }

    private static func pdfDestination(for outline: PDFOutline) -> PDFDestination? {
        if let destination = outline.destination {
            return destination
        }
        if let action = outline.action as? PDFActionGoTo {
            return action.destination
        }
        return nil
    }

    private static func pdfPageTOCItems(from document: PDFDocument, displayBox: PDFDisplayBox) -> PDFTOC {
        var destinations: [String: PDFTOCDestination] = [:]
        let items = (0..<document.pageCount).compactMap { index -> ReaderTOCItem? in
            guard let page = document.page(at: index) else { return nil }
            let id = "pdf-page-\(index)"
            let bounds = page.bounds(for: displayBox)
            destinations[id] = PDFTOCDestination(pageIndex: index, point: NSPoint(x: bounds.minX, y: bounds.maxY))
            return ReaderTOCItem(
                title: AppText.localized("第 \(index + 1) 页", "Page \(index + 1)"),
                href: id,
                level: 0
            )
        }
        return PDFTOC(items: items, destinations: destinations)
    }

    private static func jsStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(encoded.dropFirst().dropLast())
    }
}

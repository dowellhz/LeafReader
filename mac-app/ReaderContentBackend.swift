import CoreGraphics
import PDFKit
import WebKit

enum ReaderContentBackendKind: Equatable {
    case pdf
    case web
}

enum ReaderZoomStep: Equatable {
    case increment
    case decrement
}

enum ReaderPageScrollDirection: Equatable {
    case previous
    case next
}

enum ReaderPagePlacement: Equatable {
    case top
    case bottom
}

struct ReaderPagedViewportAnchor: Equatable {
    let pageIndex: Int
    let point: CGPoint
}

protocol ReaderContentBackend: AnyObject {
    var kind: ReaderContentBackendKind { get }
    var zoomPercent: Int? { get }

    func focus()
    func clearSelection()
    @discardableResult func setZoomPercent(_ percent: Int) -> Int?
    @discardableResult func stepZoom(_ step: ReaderZoomStep) -> Int?
}

protocol ReaderPagedBackend: ReaderContentBackend {
    var currentPageIndex: Int? { get }
    var pageCount: Int { get }
    var viewportAnchor: ReaderPagedViewportAnchor? { get }

    @discardableResult func navigate(toPage index: Int, placement: ReaderPagePlacement) -> Bool
    @discardableResult func restoreViewportAnchor(_ anchor: ReaderPagedViewportAnchor) -> Bool
}

protocol ReaderContinuousBackend: ReaderContentBackend {
    func scrollByPage(_ direction: ReaderPageScrollDirection)
    func scrollToCover()
    func scroll(toProgress progress: Double, animated: Bool)
}

final class PDFKitReaderAdapter: ReaderPagedBackend {
    private weak var view: PDFView?

    init(view: PDFView) {
        self.view = view
    }

    let kind: ReaderContentBackendKind = .pdf

    var currentPageIndex: Int? {
        guard let view, let document = view.document, let page = view.currentPage else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index
    }

    var pageCount: Int {
        view?.document?.pageCount ?? 0
    }

    var viewportAnchor: ReaderPagedViewportAnchor? {
        guard let view, let document = view.document, document.pageCount > 0 else { return nil }
        let anchorInView = CGPoint(
            x: view.bounds.midX,
            y: max(view.bounds.minY, view.bounds.maxY - ReaderSessionPolicy.pdfViewportAnchorTopInset)
        )
        guard let page = view.page(for: anchorInView, nearest: true) ?? view.currentPage else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        return ReaderPagedViewportAnchor(pageIndex: pageIndex, point: view.convert(anchorInView, to: page))
    }

    var zoomPercent: Int? {
        view.map { Int(round($0.scaleFactor * 100)) }
    }

    func focus() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }

    func clearSelection() {
        view?.clearSelection()
    }

    @discardableResult
    func setZoomPercent(_ percent: Int) -> Int? {
        guard let view else { return nil }
        view.autoScales = false
        view.scaleFactor = min(max(CGFloat(percent) / 100, 0.1), 8)
        return zoomPercent
    }

    @discardableResult
    func stepZoom(_ step: ReaderZoomStep) -> Int? {
        guard let view else { return nil }
        let multiplier: CGFloat = step == .increment ? 1.25 : 0.8
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * multiplier, 0.1), 8)
        return zoomPercent
    }

    @discardableResult
    func navigate(toPage index: Int, placement: ReaderPagePlacement) -> Bool {
        guard let view, let page = view.document?.page(at: index) else { return false }
        DispatchQueue.main.async { [weak view] in
            guard let view, view.document?.index(for: page) != NSNotFound else { return }
            let bounds = page.bounds(for: view.displayBox)
            let destinationY = placement == .top ? bounds.maxY : bounds.minY
            view.go(to: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: destinationY)))
        }
        return true
    }

    @discardableResult
    func restoreViewportAnchor(_ anchor: ReaderPagedViewportAnchor) -> Bool {
        guard let view, let page = view.document?.page(at: anchor.pageIndex) else { return false }
        DispatchQueue.main.async { [weak view] in
            guard let view, view.document?.index(for: page) != NSNotFound else { return }
            view.go(to: PDFDestination(page: page, at: anchor.point))
        }
        return true
    }
}

final class WebKitReaderAdapter: ReaderContinuousBackend {
    private weak var view: WKWebView?
    private var appliedZoomPercent: Int

    init(view: WKWebView, initialZoomPercent: Int = 100) {
        self.view = view
        appliedZoomPercent = initialZoomPercent
    }

    let kind: ReaderContentBackendKind = .web
    var zoomPercent: Int? { appliedZoomPercent }

    func focus() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }

    func clearSelection() {
        view?.evaluateJavaScript("window.leafReaderClearSelection && window.leafReaderClearSelection();")
    }

    @discardableResult
    func setZoomPercent(_ percent: Int) -> Int? {
        let clamped = min(max(percent, 60), 220)
        appliedZoomPercent = clamped
        guard let view else { return nil }
        view.pageZoom = 1
        view.evaluateJavaScript("""
        document.documentElement.style.setProperty('--reader-zoom', '\(Double(clamped) / 100)');
        """)
        return clamped
    }

    @discardableResult
    func stepZoom(_ step: ReaderZoomStep) -> Int? {
        setZoomPercent(appliedZoomPercent + (step == .increment ? 10 : -10))
    }

    func scrollByPage(_ direction: ReaderPageScrollDirection) {
        let sign = direction == .previous ? "-" : ""
        view?.evaluateJavaScript(
            "window.scrollBy({top: \(sign)Math.max(240, window.innerHeight * 0.86), behavior: 'smooth'});"
        )
    }

    func scrollToCover() {
        view?.evaluateJavaScript("""
        (() => {
          const cover = document.querySelector('section.reader-section[data-leaf-cover="true"]') || document.querySelector('section.reader-section');
          if (cover) {
            cover.scrollIntoView({behavior:'smooth', block:'start'});
          } else {
            window.scrollTo({top:0, behavior:'smooth'});
          }
        })();
        """)
    }

    func scroll(toProgress progress: Double, animated: Bool) {
        let clampedProgress = min(1, max(0, progress))
        let behavior = animated ? "smooth" : "auto"
        view?.evaluateJavaScript("""
        (() => {
          const progress = \(clampedProgress);
          const scroll = () => {
            const scrollHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
            window.scrollTo({ top: scrollHeight * progress, behavior: '\(behavior)' });
          };
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => requestAnimationFrame(scroll), { once: true });
          } else {
            requestAnimationFrame(() => requestAnimationFrame(scroll));
          }
        })();
        """)
    }
}

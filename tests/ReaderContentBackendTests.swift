import CoreGraphics
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("ReaderContentBackendTests failed: \(message)\n", stderr)
        exit(1)
    }
}

private final class FakePagedReaderBackend: ReaderPagedBackend {
    let kind: ReaderContentBackendKind = .pdf
    let pageCount = 3
    private(set) var currentPageIndex: Int? = 0
    private(set) var zoomPercent: Int? = 100
    private(set) var didFocus = false
    private(set) var didClearSelection = false
    private(set) var lastPlacement: ReaderPagePlacement?
    private(set) var restoredAnchor: ReaderPagedViewportAnchor?

    var viewportAnchor: ReaderPagedViewportAnchor? {
        currentPageIndex.map { ReaderPagedViewportAnchor(pageIndex: $0, point: .zero) }
    }

    func focus() {
        didFocus = true
    }

    func clearSelection() {
        didClearSelection = true
    }

    func setZoomPercent(_ percent: Int) -> Int? {
        zoomPercent = min(max(percent, 10), 800)
        return zoomPercent
    }

    func stepZoom(_ step: ReaderZoomStep) -> Int? {
        setZoomPercent((zoomPercent ?? 100) + (step == .increment ? 10 : -10))
    }

    func navigate(toPage index: Int, placement: ReaderPagePlacement) -> Bool {
        guard (0..<pageCount).contains(index) else { return false }
        currentPageIndex = index
        lastPlacement = placement
        return true
    }

    func restoreViewportAnchor(_ anchor: ReaderPagedViewportAnchor) -> Bool {
        guard (0..<pageCount).contains(anchor.pageIndex) else { return false }
        restoredAnchor = anchor
        return true
    }
}

@main
private struct ReaderContentBackendTestRunner {
    static func main() {
        let backend = FakePagedReaderBackend()
        let content: ReaderContentBackend = backend
        let paged: ReaderPagedBackend = backend

        expect(content.kind == .pdf, "the typed backend should expose its renderer kind")
        expect(content.setZoomPercent(1_000) == 800, "zoom should be clamped by the backend")
        expect(content.stepZoom(.decrement) == 790, "zoom commands should route through the backend")
        content.clearSelection()
        content.focus()
        expect(backend.didClearSelection, "selection clearing should route through the backend")
        expect(backend.didFocus, "focus should route through the backend")

        expect(paged.navigate(toPage: 2, placement: .bottom), "valid navigation should succeed")
        expect(paged.currentPageIndex == 2, "navigation should update the active page")
        expect(backend.lastPlacement == .bottom, "navigation should preserve page placement")
        expect(!paged.navigate(toPage: 3, placement: .top), "out-of-range navigation should fail")

        let anchor = ReaderPagedViewportAnchor(pageIndex: 1, point: CGPoint(x: 12, y: 34))
        expect(paged.restoreViewportAnchor(anchor), "valid viewport anchors should restore")
        expect(backend.restoredAnchor == anchor, "the complete viewport anchor should be forwarded")

        print("ReaderContentBackendTests passed")
    }
}

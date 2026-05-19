import Cocoa
import CryptoKit
import PDFKit

extension RecentDocumentsPanelController {
    func recentBookCard(
        for item: RecentDocumentItem,
        primaryText: NSColor,
        secondaryText: NSColor,
        isDark: Bool
    ) -> RecentBookCardView {
        let card = RecentBookCardView(path: item.path)
        card.translatesAutoresizingMaskIntoConstraints = false

        let cover = NSImageView()
        let coverKey = coverCacheKey(for: item)
        if let cachedCover = Self.coverCache[coverKey] {
            cover.image = cachedCover
        } else {
            cover.image = cachedPlaceholderCover(title: displayTitle(for: item), kind: item.kind, isDark: isDark)
            loadCoverImageAsync(for: item, imageView: cover)
        }
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.backgroundColor = (isDark
            ? NSColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.985, alpha: 1)
        ).cgColor
        cover.layer?.cornerRadius = 4
        cover.layer?.masksToBounds = true
        cover.layer?.borderWidth = 0.5
        cover.layer?.borderColor = NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.08).cgColor
        cover.translatesAutoresizingMaskIntoConstraints = false

        let shadowHost = NSView()
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = isDark ? 0.32 : 0.20
        shadowHost.layer?.shadowRadius = 9
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -4)
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        shadowHost.addSubview(cover)

        let title = NSTextField(labelWithString: displayTitle(for: item))
        title.font = AppFont.semibold(ofSize: 13)
        title.textColor = primaryText
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: displaySubtitle(for: item))
        subtitle.font = AppFont.semibold(ofSize: 12)
        subtitle.textColor = secondaryText
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let progressLabel = NSTextField(labelWithString: progressText(for: item))
        progressLabel.font = AppFont.semibold(ofSize: 11)
        progressLabel.textColor = secondaryText.withAlphaComponent(0.92)
        progressLabel.lineBreakMode = .byTruncatingTail
        progressLabel.maximumNumberOfLines = 1
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [shadowHost, title, subtitle, progressLabel] {
            card.addSubview(view)
        }

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: coverSize.width),
            card.heightAnchor.constraint(equalToConstant: coverSize.height + 104),

            shadowHost.topAnchor.constraint(equalTo: card.topAnchor),
            shadowHost.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            shadowHost.widthAnchor.constraint(equalToConstant: coverSize.width),
            shadowHost.heightAnchor.constraint(equalToConstant: coverSize.height),
            cover.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            cover.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),

            title.topAnchor.constraint(equalTo: shadowHost.bottomAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            progressLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 5),
            progressLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            progressLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -4)
        ])
        return card
    }

    func coverCacheKey(for item: RecentDocumentItem) -> String {
        let url = URL(fileURLWithPath: item.path)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        let digest = SHA256.hash(data: Data("\(item.path)#\(item.kind)#\(ReaderTheme.selected.rawValue)#\(modified)#\(fileSize)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func loadCoverImageAsync(for item: RecentDocumentItem, imageView: NSImageView) {
        let cacheKey = coverCacheKey(for: item)
        let path = item.path
        let kind = item.kind
        let coverSize = self.coverSize
        Self.coverLoadQueue.addOperation { [weak self, weak imageView] in
            guard let self else { return }
            if let diskCover = self.loadDiskCover(cacheKey: cacheKey) {
                DispatchQueue.main.async {
                    Self.coverCache[cacheKey] = diskCover
                    guard let imageView else { return }
                    imageView.image = diskCover
                }
                return
            }

            let url = URL(fileURLWithPath: path)
            if kind == "EPUB" {
                guard let coverData = try? WebDocumentLoader.coverImageData(forEPUB: url),
                      let image = NSImage(data: coverData) else { return }
                image.size = coverSize
                image.cacheMode = .always
                DispatchQueue.main.async {
                    Self.coverCache[cacheKey] = image
                    self.saveDiskCover(image, cacheKey: cacheKey)
                    guard let imageView else { return }
                    imageView.image = image
                }
                return
            }

            guard kind == "PDF" else { return }
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: 0) else { return }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let renderScale = max(2, min(3, scale))
            let targetSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
            let image = page.thumbnail(of: targetSize, for: .cropBox)
            image.size = coverSize
            image.cacheMode = .always
            DispatchQueue.main.async {
                Self.coverCache[cacheKey] = image
                self.saveDiskCover(image, cacheKey: cacheKey)
                guard let imageView else { return }
                imageView.image = image
            }
        }
    }

    func cachedPlaceholderCover(title: String, kind: String, isDark: Bool) -> NSImage {
        let cacheKey = "\(ReaderTheme.selected.rawValue)#\(kind)#\(title)"
        if let cached = Self.placeholderCoverCache[cacheKey] {
            return cached
        }
        let image = placeholderCover(title: title, kind: kind, isDark: isDark)
        Self.placeholderCoverCache[cacheKey] = image
        return image
    }

    func loadDiskCover(cacheKey: String) -> NSImage? {
        guard let url = diskCoverURL(cacheKey: cacheKey) else { return nil }
        return NSImage(contentsOf: url)
    }

    func saveDiskCover(_ image: NSImage, cacheKey: String) {
        guard let url = diskCoverURL(cacheKey: cacheKey),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func diskCoverURL(cacheKey: String) -> URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory
            .appendingPathComponent("LeafReader", isDirectory: true)
            .appendingPathComponent("ShelfCovers", isDirectory: true)
            .appendingPathComponent("\(cacheKey).png")
    }

    func highResolutionPDFCover(page: PDFPage) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderScale = max(2, min(3, scale))
        let targetSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
        let image = page.thumbnail(of: targetSize, for: .cropBox)
        image.size = coverSize
        image.cacheMode = .always
        return image
    }

    func placeholderCover(title: String, kind: String, isDark: Bool) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderScale = max(2, min(3, scale))
        let renderSize = NSSize(width: coverSize.width * renderScale, height: coverSize.height * renderScale)
        let image = NSImage(size: coverSize)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(renderSize.width),
            pixelsHigh: Int(renderSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap else { return image }
        bitmap.size = coverSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(origin: .zero, size: coverSize)
        let background = isDark
            ? NSColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1)
            : NSColor.white
        background.setFill()
        rect.fill()
        (isDark
            ? NSColor(red: 0.28, green: 0.32, blue: 0.39, alpha: 1)
            : NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        ).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 13),
            .foregroundColor: isDark ? NSColor.white : NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let kindAttributes: [NSAttributedString.Key: Any] = [
            .font: AppFont.semibold(ofSize: 9),
            .foregroundColor: isDark ? NSColor(red: 0.70, green: 0.76, blue: 0.84, alpha: 1) : NSColor(red: 0.35, green: 0.39, blue: 0.48, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let trimmedTitle = title.count > 34 ? String(title.prefix(34)) : title
        NSString(string: trimmedTitle).draw(in: NSRect(x: 14, y: coverSize.height * 0.48, width: coverSize.width - 28, height: 54), withAttributes: titleAttributes)
        NSString(string: documentKindText(kind)).draw(in: NSRect(x: 12, y: 18, width: coverSize.width - 24, height: 18), withAttributes: kindAttributes)
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(bitmap)
        return image
    }

    func displayTitle(for item: RecentDocumentItem) -> String {
        return item.title
    }

    func displaySubtitle(for item: RecentDocumentItem) -> String {
        documentKindText(item.kind)
    }

    func documentKindText(_ kind: String) -> String {
        switch kind {
        case "EPUB":
            return AppText.localized("EPUB 书籍", "EPUB Book")
        case "DOCX":
            return AppText.localized("DOCX 文稿", "DOCX Document")
        default:
            return AppText.localized("PDF 书籍", "PDF Book")
        }
    }

    func progressText(for item: RecentDocumentItem) -> String {
        guard let progress = item.readingProgress else {
            return AppText.localized("未记录进度", "No progress")
        }
        let percent = min(100, max(0, Int((progress * 100).rounded())))
        return AppText.localized("已读 \(percent)%", "\(percent)% read")
    }}

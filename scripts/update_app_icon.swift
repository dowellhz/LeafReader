#!/usr/bin/env swift
import AppKit
import Foundation

struct IconUpdater {
    let root: URL
    let sourceURL: URL
    let maskRounded: Bool

    func run() throws {
        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw NSError(domain: "IconUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read source image: \(sourceURL.path)"])
        }

        let appIconSource = root.appendingPathComponent("mac-app/AppIconSource.png")
        let source1024 = try render(image: sourceImage, size: 1024, roundedMask: maskRounded)
        try writePNG(source1024, to: appIconSource)
        try writePNG(source1024, to: root.appendingPathComponent("assets/leaf-reader-icon.png"))
        try writePNG(source1024, to: root.appendingPathComponent("docs/assets/leaf-reader-icon.png"))
        try writePNG(try render(image: source1024, size: 48, roundedMask: false), to: root.appendingPathComponent("docs/manual/assets/images/favicon.png"))

        let iconset = root.appendingPathComponent("mac-app/AppIcon.iconset")
        let outputs: [(String, Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for (name, size) in outputs {
            try writePNG(try render(image: source1024, size: size, roundedMask: false), to: iconset.appendingPathComponent(name))
        }

        try writeICNS(
            entries: [
                ("icp4", iconset.appendingPathComponent("icon_16x16.png")),
                ("icp5", iconset.appendingPathComponent("icon_32x32.png")),
                ("icp6", iconset.appendingPathComponent("icon_32x32@2x.png")),
                ("ic07", iconset.appendingPathComponent("icon_128x128.png")),
                ("ic08", iconset.appendingPathComponent("icon_256x256.png")),
                ("ic09", iconset.appendingPathComponent("icon_512x512.png")),
                ("ic10", iconset.appendingPathComponent("icon_512x512@2x.png"))
            ],
            to: root.appendingPathComponent("mac-app/AppIcon.icns")
        )
    }

    private func render(image: NSImage, size: Int, roundedMask: Bool) throws -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "IconUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate bitmap"])
        }

        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.clear.setFill()
        rect.fill()
        if roundedMask {
            let radius = CGFloat(size) * 0.166
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        }
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let output = NSImage(size: NSSize(width: size, height: size))
        output.addRepresentation(rep)
        return output
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconUpdater", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PNG: \(url.path)"])
        }
        try rep.write(to: url)
    }

    private func writeICNS(entries: [(String, URL)], to url: URL) throws {
        var body = Data()
        for (type, entryURL) in entries {
            let png = try Data(contentsOf: entryURL)
            body.append(Data(type.utf8))
            body.append(bigEndianUInt32(UInt32(png.count + 8)))
            body.append(png)
        }

        var output = Data()
        output.append(Data("icns".utf8))
        output.append(bigEndianUInt32(UInt32(body.count + 8)))
        output.append(body)
        try output.write(to: url)
    }

    private func bigEndianUInt32(_ value: UInt32) -> Data {
        var big = value.bigEndian
        return Data(bytes: &big, count: MemoryLayout<UInt32>.size)
    }
}

let args = CommandLine.arguments.dropFirst()
guard let source = args.first, !source.hasPrefix("-") else {
    fputs("Usage: scripts/update_app_icon.swift <source-png> [--mask-rounded]\n", stderr)
    exit(64)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = URL(fileURLWithPath: source)
let updater = IconUpdater(root: root, sourceURL: sourceURL, maskRounded: args.contains("--mask-rounded"))

do {
    try updater.run()
} catch {
    fputs("update_app_icon failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

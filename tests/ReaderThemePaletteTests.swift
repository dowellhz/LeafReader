import Cocoa

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

private func rgba(_ color: NSColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    guard let converted = color.usingColorSpace(.deviceRGB) else {
        throw TestFailure(description: "color should convert to device RGB")
    }
    return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
}

private func expectVisible(_ color: NSColor, _ message: String) throws {
    let components = try rgba(color)
    try expect(components.alpha > 0.01, message)
}

private func expectDifferent(_ lhs: NSColor, _ rhs: NSColor, _ message: String) throws {
    let left = try rgba(lhs)
    let right = try rgba(rhs)
    let distance = abs(left.red - right.red)
        + abs(left.green - right.green)
        + abs(left.blue - right.blue)
        + abs(left.alpha - right.alpha)
    try expect(distance > 0.05, message)
}

private func testChromePaletteCoversAllThemes() throws {
    for theme in ReaderTheme.allCases {
        try expectVisible(theme.chromeBackgroundColor, "chrome background should be visible for \(theme)")
        try expectVisible(theme.toolbarBackgroundColor, "toolbar background should be visible for \(theme)")
        try expectVisible(theme.toolbarBorderColor, "toolbar border should be visible for \(theme)")
        try expectVisible(theme.controlBackgroundColor, "control background should be visible for \(theme)")
        try expectVisible(theme.controlBorderColor, "control border should be visible for \(theme)")
        try expectVisible(theme.resizeHandleColor, "resize handle should be visible for \(theme)")
    }

    try expectDifferent(
        ReaderTheme.original.chromeBackgroundColor,
        ReaderTheme.eyeCare.chromeBackgroundColor,
        "eye-care chrome should not reuse original chrome background"
    )
    try expectDifferent(
        ReaderTheme.original.toolbarBackgroundColor,
        ReaderTheme.dark.toolbarBackgroundColor,
        "dark toolbar should not reuse original toolbar background"
    )
}

private func testSearchOverlayPaletteCoversAllThemes() throws {
    for theme in ReaderTheme.allCases {
        try expectVisible(theme.searchOverlayBackgroundColor, "search overlay background should be visible for \(theme)")
        try expectVisible(theme.searchOverlaySeparatorColor, "search overlay separator should be visible for \(theme)")
    }

    try expectDifferent(
        ReaderTheme.eyeCare.searchOverlayBackgroundColor,
        ReaderTheme.dark.searchOverlayBackgroundColor,
        "search overlay background should change between eye-care and dark themes"
    )
    try expectDifferent(
        ReaderTheme.original.searchOverlaySeparatorColor,
        ReaderTheme.dark.searchOverlaySeparatorColor,
        "search overlay separator should change between original and dark themes"
    )
}

@main
private enum ReaderThemePaletteTestRunner {
    static func main() {
        do {
            try testChromePaletteCoversAllThemes()
            try testSearchOverlayPaletteCoversAllThemes()
            print("ReaderThemePaletteTests passed")
        } catch {
            fputs("ReaderThemePaletteTests failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

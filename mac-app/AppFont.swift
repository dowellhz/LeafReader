import Cocoa

enum AppFont {
    static func semibold(ofSize size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Semibold", size: size)
            ?? NSFont(name: "PingFang SC Semibold", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }
}

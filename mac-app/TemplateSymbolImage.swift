import Cocoa

enum TemplateSymbolImage {
    static func make(_ name: String, accessibilityDescription: String? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }
}

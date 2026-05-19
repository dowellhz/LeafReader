import Cocoa
import UniformTypeIdentifiers

enum DocumentOpenPanelConfiguration {
    static let contentTypes: [UTType] = [.pdf, .epub, .init(filenameExtension: "docx")].compactMap { $0 }

    static func apply(to panel: NSOpenPanel) {
        panel.allowedContentTypes = contentTypes
        panel.allowsOtherFileTypes = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
    }
}

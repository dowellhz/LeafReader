import Cocoa

extension AppDelegate {
    private static let onlineHelpURL = URL(string: "https://leafreader.space/manual/getting-started/")!

    @objc func showLeafReaderHelp(_ sender: Any?) {
        NSWorkspace.shared.open(Self.onlineHelpURL)
    }
}

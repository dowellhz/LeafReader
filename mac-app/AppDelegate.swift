import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ReaderWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = ReaderWindowController()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        controller.window?.makeKeyAndOrderFront(nil)
        controller.openDocument(URL(fileURLWithPath: filename))
        return true
    }
}

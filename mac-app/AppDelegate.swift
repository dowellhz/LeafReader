import Cocoa
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let updateWindowOpenRetryLimit = 20
    static let updateWindowOpenRetryDelay: TimeInterval = 0.15

    var controller: ReaderWindowController!
    var helpWindow: NSWindow?
    var aboutWindow: NSWindow?
    var updateStatusWindow: NSWindow?
    var updaterController: SPUStandardUpdaterController?
    var manualUpdateProbeInProgress = false
    var manualUpdateProbeFoundUpdate = false
    var manualUpdateProbeHandledResult = false
    weak var manualUpdateSender: AnyObject?
    var pendingOpenFileURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller = ReaderWindowController()
        installMainMenu()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadPendingOpenFilesIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFileURLWhenReady(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.map { URL(fileURLWithPath: $0) }.forEach(openFileURLWhenReady)
        sender.reply(toOpenOrPrint: .success)
    }

    func openFileURLWhenReady(_ url: URL) {
        guard let controller else {
            pendingOpenFileURLs.append(url)
            return
        }
        openFileURL(url, in: controller)
    }

    func loadPendingOpenFilesIfNeeded() {
        guard let url = pendingOpenFileURLs.last else { return }
        pendingOpenFileURLs.removeAll()
        openFileURL(url, in: controller)
    }

    func openFileURL(_ url: URL, in controller: ReaderWindowController) {
        controller.window?.makeKeyAndOrderFront(nil)
        controller.openDocument(url)
    }

}

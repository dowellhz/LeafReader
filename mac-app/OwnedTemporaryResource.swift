import Foundation

final class OwnedTemporaryResource {
    let url: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var isReleased = false

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func release() {
        lock.lock()
        guard !isReleased else {
            lock.unlock()
            return
        }
        isReleased = true
        lock.unlock()
        do {
            try fileManager.removeItem(at: url)
        } catch where (error as NSError).code == NSFileNoSuchFileError {
            return
        } catch {
            NSLog("LeafReader temporary resource: cleanup failed at %@ (%@)", url.path, error.localizedDescription)
        }
    }

    deinit {
        release()
    }
}

import Foundation

extension ReaderWindowController {
    func prepareForUserDataBackup() {
        performSessionSave()
        flushPendingAIConversationSave()
        flushCurrentBookWordRecordSaves(waitForCompletion: true)
        UserDefaults.standard.synchronize()
    }
}

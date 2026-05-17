import Foundation

enum ReaderDocumentImportCoordinator {
    static func handleDroppedDocumentURLs(_ urls: [URL], controller: ReaderWindowController) {
        let supported = RecentDocumentsStore.supportedUniqueURLs(urls)
        guard !supported.isEmpty else { return }
        let supportedDropCount = urls.filter { ReaderDocumentKind.kind(for: $0) != nil }.count
        if supportedDropCount == 1, supported.count == 1 {
            openSingleDroppedDocument(supported[0], controller: controller)
            return
        }
        importDroppedDocumentsToShelf(supported, controller: controller)
    }

    static func openSingleDroppedDocument(_ url: URL, controller: ReaderWindowController) {
        controller.aiSettingsPanelController?.closeWithoutSaving()
        controller.aiSettingsPanelController = nil
        if let vocabularyPanel = controller.vocabularyPanel {
            controller.closeVocabularyPanel(vocabularyPanel)
        }
        if let recentDocumentsPanelController = controller.recentDocumentsPanelController {
            recentDocumentsPanelController.closeThenOpen(path: url.path)
            return
        }
        controller.loadDocument(url)
    }

    static func importDroppedDocumentsToShelf(_ urls: [URL], controller: ReaderWindowController) {
        let importedPaths = RecentDocumentsStore.record(urls: urls)
        let focusPath = importedPaths.first
        if let recentDocumentsPanelController = controller.recentDocumentsPanelController {
            recentDocumentsPanelController.close()
            DispatchQueue.main.async { [weak controller] in
                controller?.showRecentDocumentsPanel(focusPath: focusPath, priorityPaths: importedPaths)
            }
        } else {
            controller.showRecentDocumentsPanel(focusPath: focusPath)
        }
    }
}

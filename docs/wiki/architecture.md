# Architecture

Leaf Reader is a native macOS reader built with Swift, PDFKit, WebKit, and Sparkle.

## Main Flow

```text
AppDelegate
  -> ReaderWindowController
     -> DocumentLoading
     -> PDFKit PDF View
     -> WebKit EPUB/DOCX View
     -> AIChatPanel
        -> AIClient
     -> SQLite and local stores
```

## Key Areas

- `AppDelegate*.swift`: app lifecycle, menu, help, update UI.
- `ReaderWindowController*.swift`: reader shell, document opening, navigation, search, AI integration, vocabulary, sessions.
- `DocumentLoading*.swift`: EPUB/DOCX archive handling, HTML generation, shared document helpers.
- `AIChatPanel*.swift`: AI chat UI, request lifecycle, bubble layout, selection handling.
- `AISettingsPanelController*.swift`: settings window, model configuration, AI analysis cache controls.
- `RecentDocuments*.swift` and `RecentBookCardView.swift`: bookshelf panel and recent document UI.
- `WordRecordSQLiteStore.swift` and related stores: persistent word and conversation data.

## Design Rule

Large controllers are split by behavior into extensions or focused helper views. New work should prefer adding to an existing focused module instead of growing a general controller file.

## Related Files

- `mac-app/AppDelegate.swift`
- `mac-app/ReaderWindowController.swift`
- `mac-app/ReaderWindowController+UI.swift`
- `mac-app/DocumentLoading.swift`
- `mac-app/AIChatPanel.swift`
- `mac-app/WordRecordSQLiteStore.swift`

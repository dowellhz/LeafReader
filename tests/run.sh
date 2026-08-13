#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_swift_test() {
  local output="$1"
  shift
  swiftc "$@" -o "$output"
  "$output"
}

LOGIC_APP_SOURCES=()

always_include_logic_app_source() {
  local base="$1"
  case "$base" in
    ReadingNoteEditorViews.swift|SelectionToolbarConfiguration.swift)
      return 0
      ;;
  esac
  return 1
}

excluded_logic_app_source() {
  local base="$1"
  case "$base" in
    main.swift|\
    AppDelegate*|\
    AIChatPanel*|\
    AISettingsPanel*|\
    AITextActionRunner.swift|\
    AIClient.swift|\
    DebouncedTask.swift|\
    DiagnosticsPanel*|\
    DiagnosticsReport.swift|\
    DocumentLoading*|\
    DocumentQuestionPromptRequest.swift|\
    EmbeddingClient.swift|\
    KokoroTTSBackend.swift|\
    LeafAlertStyle.swift|\
    LLMAnswerProvider.swift|\
    ModalOverlayManager.swift|\
    PDFDocumentAgentIndex.swift|\
    PDFEmbeddingStore.swift|\
    PDFWordRecordStore.swift|\
    Reader*State.swift|\
    ReaderDocumentImportCoordinator.swift|\
    ReaderDropContentView.swift|\
    ReaderFileDrop.swift|\
    ReaderTheme*|\
    ReaderTOCHelper.swift|\
    ReaderAIPanelCoordinator.swift|\
    ReaderReadAloudCoordinator.swift|\
    ReaderSelectionCoordinator.swift|\
    ReaderWindowController*|\
    ReaderWindowSupportViews.swift|\
    ReadingNotePanelController*|\
    ReadingNoteEditorRenderer.swift|\
    ReadingNoteTheme.swift|\
    RecentDocuments*|\
    SearchOverlayView.swift|\
    SelectionActionToolbar.swift|\
    SelectionToolbarCoordinator.swift|\
    SettingsTabsView.swift|\
    SpeechPlayback*|\
    TemplateSymbolImage.swift|\
    ThemedSettings*|\
    TTSPreviewCache.swift|\
    VocabularyContextProvider.swift|\
    VocabularyDictionaryMetadataService.swift|\
    VocabularyFrequencyBackfillService.swift|\
    VocabularyRecordProvider.swift|\
    VocabularyReviewCardFooterBuilder.swift|\
    VocabularyReviewCoordinator.swift|\
    VocabularyReviewScoringService.swift|\
    VocabularySpeechCoordinator.swift|\
    WebReadAloudBatchParser.swift|\
    WebWordRecordStore.swift|\
    WordRecordSQLite*.swift|\
    *Button.swift|\
    *Controls.swift|\
    *Overlay*.swift|\
    *Toolbar*.swift|\
    *View.swift|\
    *Views.swift)
      return 0
      ;;
  esac
  return 1
}

contains_ui_dependency() {
  local source="$1"
  grep -Eq '\b(NSView|NSWindow|NSButton|NSImageView|NSPanel|NSScrollView|WKWebView|PDFView|PDFAnnotation|AVAudio|NSSavePanel|NSOpenPanel|NSMenu|NSAlert|NSCollectionView|NSTextView|NSVisualEffectView|NSToolbar)\b' "$source"
}

collect_logic_app_sources() {
  local source
  local base
  LOGIC_APP_SOURCES=()

  while IFS= read -r source; do
    base="${source##*/}"
    if always_include_logic_app_source "$base"; then
      LOGIC_APP_SOURCES+=("$source")
      continue
    fi
    if excluded_logic_app_source "$base" || contains_ui_dependency "$source"; then
      continue
    fi
    LOGIC_APP_SOURCES+=("$source")
  done < <(find mac-app -maxdepth 1 -name "*.swift" -type f | sort)
}

SQLITE_WORD_TEST_SOURCES=(
  tests/SQLiteWordRecordStoreTests.swift
  mac-app/VocabularySRS.swift
  mac-app/StoredPDFWordRect.swift
  mac-app/PDFWordRecordStore.swift
  mac-app/WebWordRecordStore.swift
  mac-app/SQLiteSchemaMigrator.swift
  mac-app/SQLiteTransactionExecutor.swift
  mac-app/WordRecordSQLiteRowMapper.swift
  mac-app/WordRecordSQLiteStore.swift
)

PERSONAL_VOCABULARY_TEST_SOURCES=(
  tests/PersonalVocabularyProfileStoreTests.swift
  mac-app/PersonalVocabularyProfile.swift
  mac-app/PersonalVocabularyProfileSchema.swift
  mac-app/SQLiteSchemaMigrator.swift
  mac-app/SQLiteTransactionExecutor.swift
  mac-app/PersonalVocabularyProfileStore.swift
)

REGRESSION_TEST_SOURCES=(
  mac-app/ProcessRunner.swift
  mac-app/LaunchPerformanceTracker.swift
  mac-app/AIRequestState.swift
  mac-app/MarkdownRenderer.swift
  mac-app/MarkdownBlockParser.swift
  mac-app/MarkdownInlineParser.swift
  mac-app/DocumentIdentity.swift
  mac-app/StoredPDFWordRect.swift
  mac-app/AIConversationStore.swift
  tests/RegressionTests.swift
)

LOGIC_TEST_SOURCES=(
  tests/AIConversationContextStoreTests.swift
  tests/EPUBLogicTests.swift
  tests/ReadingNoteLogicTests.swift
  tests/ReadingNoteMarkdownLogicTests.swift
  tests/ReaderShelfLogicTests.swift
  tests/AISettingsTestSupport.swift
  tests/AISettingsLogicTests.swift
  tests/SpeechRuntimeLogicTests.swift
  tests/SpeechRuntimeBackendTests.swift
  tests/SpeechRuntimeDownloadTests.swift
  tests/SpeechRuntimeManifestTests.swift
  tests/SpeechRuntimeAvailabilityTests.swift
  tests/SecurityHardeningTests.swift
  tests/ECDICTLogicTests.swift
  tests/VocabularyLogicTests.swift
  tests/ReaderCoreLogicTests.swift
  tests/ReaderReadAloudLogicTests.swift
  tests/LogicTests.swift
)

node --check mac-app/Resources/reader-web-text.js
node --check mac-app/Resources/reader-web-overlay.js
node --check mac-app/Resources/reader-web-search.js
node --check mac-app/Resources/reader-web-marks.js
node --check mac-app/Resources/reader-web-tts.js
node --check mac-app/Resources/reader-web-selection.js
node --check mac-app/Resources/reader-web.js
node tests/ReaderWebScriptTests.js

collect_logic_app_sources

run_swift_test /tmp/leafreader-sqlite-word-tests \
  "${SQLITE_WORD_TEST_SOURCES[@]}" \
  -framework Cocoa \
  -lsqlite3

run_swift_test /tmp/leafreader-personal-vocabulary-tests \
  "${PERSONAL_VOCABULARY_TEST_SOURCES[@]}" \
  -lsqlite3

run_swift_test /tmp/leafreader-pdf-embedding-store-tests \
  tests/PDFEmbeddingStoreTests.swift \
  mac-app/PDFEmbeddingStore.swift \
  mac-app/SQLiteTransactionExecutor.swift \
  mac-app/PDFDocumentAgentIndex.swift \
  mac-app/ReaderAIContextBuilder.swift \
  mac-app/ReaderAIContextBuilder+PDF.swift \
  mac-app/ReaderAIContextPolicy.swift \
  mac-app/AppText.swift \
  -framework PDFKit \
  -framework Cocoa \
  -lsqlite3

run_swift_test /tmp/leafreader-regression-tests \
  "${REGRESSION_TEST_SOURCES[@]}" \
  -framework Cocoa

run_swift_test /tmp/leafreader-update-failure-classifier-tests \
  mac-app/UpdateFailureClassifier.swift \
  tests/UpdateFailureClassifierTests.swift

run_swift_test /tmp/leafreader-theme-palette-tests \
  mac-app/AppText.swift \
  mac-app/ReaderTheme.swift \
  mac-app/ReaderTheme+Palette.swift \
  tests/ReaderThemePaletteTests.swift \
  -framework Cocoa

run_swift_test /tmp/leafreader-logic-tests \
  "${LOGIC_APP_SOURCES[@]}" \
  "${LOGIC_TEST_SOURCES[@]}" \
  -framework PDFKit \
  -framework Cocoa \
  -framework Network \
  -lsqlite3

if [[ -n "${LEAFREADER_TEST_APP_BUNDLE:-}" ]]; then
  tests/PiperRuntimeBundleTests.sh "$LEAFREADER_TEST_APP_BUNDLE"
fi

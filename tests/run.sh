#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_swift_test() {
  local output="$1"
  shift
  swiftc "$@" -o "$output"
  "$output"
}

SQLITE_WORD_TEST_SOURCES=(
  tests/SQLiteWordRecordStoreTests.swift
  mac-app/VocabularySRS.swift
  mac-app/StoredPDFWordRect.swift
  mac-app/PDFWordRecordStore.swift
  mac-app/WebWordRecordStore.swift
  mac-app/WordRecordSQLiteRowMapper.swift
  mac-app/WordRecordSQLiteStore.swift
)

REGRESSION_TEST_SOURCES=(
  mac-app/ProcessRunner.swift
  mac-app/AIRequestState.swift
  mac-app/MarkdownRenderer.swift
  mac-app/DocumentIdentity.swift
  mac-app/StoredPDFWordRect.swift
  mac-app/AIConversationStore.swift
  tests/RegressionTests.swift
)

LOGIC_APP_SOURCES=(
  mac-app/EmbeddingWarmupPolicy.swift
  mac-app/PDFPagingPolicy.swift
  mac-app/PDFBrightnessPolicy.swift
  mac-app/StoredPDFWordRect.swift
  mac-app/ReaderSessionPolicy.swift
  mac-app/ReaderSessionStore.swift
  mac-app/ReadingNote.swift
  mac-app/ReadingNoteEditorState.swift
  mac-app/ReadingNoteSlashCommand.swift
  mac-app/ReadingNoteAITextPolicy.swift
  mac-app/ReadingNoteMarkdownInputPolicy.swift
  mac-app/MarkdownRenderer.swift
  mac-app/ReadingNoteMarkdownSerializer.swift
  mac-app/ReadingNoteTextReplacementPolicy.swift
  mac-app/ReadingNoteTextPolicy.swift
  mac-app/ReadingNoteListPresenter.swift
  mac-app/ReadingNoteStore.swift
  mac-app/ReadingNoteExporter.swift
  mac-app/ReaderProgressFormatter.swift
  mac-app/ReadAloudTextMatcher.swift
  mac-app/VocabularyTextPolicy.swift
  mac-app/ReaderAIContextPolicy.swift
  mac-app/AIResponseParser.swift
  mac-app/AIResponseTextFormatter.swift
  mac-app/ECDICTDictionary.swift
  mac-app/DictionaryLookupService.swift
  mac-app/AnswerProvider.swift
  mac-app/EmbeddingActionPolicy.swift
  mac-app/AppText.swift
  mac-app/AIProviderDescriptor.swift
  mac-app/AIModelConfig.swift
  mac-app/AIChatRequestBuilder.swift
  mac-app/LocalEncryptedStore.swift
  mac-app/LocalRuntime.swift
  mac-app/LocalRuntimeDownloadManifest.swift
  mac-app/LocalRuntimeDownloadCoordinator.swift
  mac-app/LocalRuntimeInstallCoordinator.swift
  mac-app/SpeechVoiceCatalog.swift
  mac-app/AISettingsStore.swift
  mac-app/AISettingsStore+Embedding.swift
  mac-app/AISettingsStore+Speech.swift
  mac-app/NetworkConnectivityMonitor.swift
  mac-app/NetworkErrorFormatter.swift
  mac-app/KokoroWorkerResponseReader.swift
  mac-app/ProcessRunner.swift
  mac-app/SpeechTextPolicy.swift
  mac-app/SpeechTextNormalization.swift
  mac-app/SpeechSentenceBoundary.swift
  mac-app/ReadAloudManualAdvanceKeyPolicy.swift
  mac-app/SpeechSynthesisError.swift
  mac-app/TTSWaveFile.swift
  mac-app/VocabularyAudioCache.swift
  mac-app/PiperTTSBackend.swift
  mac-app/KokoroVoiceResourceManager.swift
  mac-app/LocalRuntimeInstaller.swift
  mac-app/LocalRuntimeDownloadSupport.swift
  mac-app/SpeechRuntimeDownloadSupport.swift
  mac-app/SpeechRuntimeManifestFetcher.swift
  mac-app/SpeechRuntimeCatalog.swift
  mac-app/SpeechRuntimeModel.swift
  mac-app/SpeechRuntimeAvailability.swift
  mac-app/SpeechRuntimeStatus.swift
  mac-app/SpeechRuntimeInstaller.swift
  mac-app/SpeechRuntimeDeleter.swift
  mac-app/SpeechRuntimeDownloadFailureStore.swift
  mac-app/SpeechRuntimeInferenceFailureStore.swift
  mac-app/SpeechRuntimePathChecks.swift
  mac-app/SpeechRuntimeCacheInstallTransaction.swift
  mac-app/SpeechRuntimeInstallHelpers.swift
  mac-app/SpeechRuntimeResourceManager.swift
  mac-app/LocalRuntimeDownloader.swift
  mac-app/ReadingContextSnapshot.swift
  mac-app/ReaderDocumentKind.swift
  mac-app/VocabularyReviewModels.swift
  mac-app/VocabularyDailyGoalPolicy.swift
  mac-app/VocabularySRS.swift
  mac-app/VocabularyExportRecord.swift
  mac-app/VocabularyReviewQueueBuilder.swift
  mac-app/VocabularyReviewSession.swift
  mac-app/VocabularyReviewCardSelector.swift
  mac-app/ReaderQueryCapability.swift
  mac-app/RequestAvailabilityPolicy.swift
  mac-app/SelectionToolbarConfiguration.swift
  mac-app/VocabularyReviewDisplayRecordLoader.swift
  mac-app/VocabularyAnswerFormatter.swift
  mac-app/VocabularyExporter.swift
  mac-app/ReaderAIContextBuilder.swift
  mac-app/ReaderAIContextBuilder+PDF.swift
  mac-app/EPUBPackageParser.swift
  mac-app/EPUBPathResolver.swift
  mac-app/EPUBHTMLSanitizer.swift
  mac-app/EPUBTextDecoder.swift
)

LOGIC_TEST_SOURCES=(
  tests/EPUBLogicTests.swift
  tests/ReadingNoteLogicTests.swift
  tests/ReaderShelfLogicTests.swift
  tests/AISettingsLogicTests.swift
  tests/ECDICTLogicTests.swift
  tests/VocabularyLogicTests.swift
  tests/LogicTests.swift
)

node --check mac-app/Resources/reader-web.js
node tests/ReaderWebScriptTests.js

run_swift_test /tmp/leafreader-sqlite-word-tests \
  "${SQLITE_WORD_TEST_SOURCES[@]}" \
  -framework Cocoa \
  -lsqlite3

run_swift_test /tmp/leafreader-pdf-embedding-store-tests \
  tests/PDFEmbeddingStoreTests.swift \
  mac-app/PDFEmbeddingStore.swift \
  -lsqlite3

run_swift_test /tmp/leafreader-regression-tests \
  "${REGRESSION_TEST_SOURCES[@]}" \
  -framework Cocoa

run_swift_test /tmp/leafreader-update-failure-classifier-tests \
  mac-app/UpdateFailureClassifier.swift \
  tests/UpdateFailureClassifierTests.swift

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

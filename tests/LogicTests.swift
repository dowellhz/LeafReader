import Foundation
import CoreGraphics

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw TestFailure(description: "\(message). expected \(rhs), got \(lhs)")
    }
}

private let tests: [(String, () throws -> Void)] = [
    ("Vocabulary SRS", VocabularyLogicTests.testVocabularySRS),
    ("Vocabulary review card selector", VocabularyLogicTests.testVocabularyReviewCardSelector),
    ("Vocabulary daily goal policy", VocabularyLogicTests.testVocabularyDailyGoalPolicy),
    ("Vocabulary learning stats", VocabularyLogicTests.testVocabularyLearningStats),
    ("Personal vocabulary tokenizer and policy", VocabularyLogicTests.testPersonalVocabularyTokenizerAndPolicy),
    ("Vocabulary answer formatter", VocabularyLogicTests.testVocabularyAnswerFormatter),
    ("Recent document sorting/import", ReaderShelfLogicTests.testRecentDocumentSortingAndImport),
    ("Dropped document actions", ReaderShelfLogicTests.testDroppedDocumentActions),
    ("Embedding defaults", AISettingsLogicTests.testEmbeddingDefaults),
    ("Secure credential migration", AISettingsLogicTests.testSecureCredentialStoreRoundTripAndLegacyMigration),
    ("Secure credential migration failure", AISettingsLogicTests.testCredentialMigrationPreservesLegacyDataOnWriteFailure),
    ("AI settings injected defaults model selection", AISettingsLogicTests.testAISettingsStoreInjectedDefaultsModelSelection),
    ("AI provider descriptors", AISettingsLogicTests.testAIProviderDescriptors),
    ("AI settings injected defaults embedding and toggles", AISettingsLogicTests.testAISettingsStoreInjectedDefaultsEmbeddingAndToggles),
    ("AI settings speech selection validation", SpeechRuntimeLogicTests.testAISettingsStoreSpeechSelectionValidation),
    ("Piper speech speed length scale", SpeechRuntimeLogicTests.testPiperSpeechSpeedLengthScale),
    ("Kokoro speech speed multiplier", SpeechRuntimeLogicTests.testKokoroSpeechSpeedMultiplier),
    ("Piper worker input line normalization", SpeechRuntimeBackendTests.testPiperWorkerInputLineNormalizesNewlines),
    ("Piper worker output path validation", SpeechRuntimeBackendTests.testPiperWorkerOutputPathValidation),
    ("Piper worker restart threshold", SpeechRuntimeBackendTests.testPiperWorkerRestartThreshold),
    ("Piper CoreML fallback diagnostics", SpeechRuntimeBackendTests.testPiperCoreMLFallbackDiagnostics),
    ("Kokoro installed voice cache key", SpeechRuntimeBackendTests.testKokoroInstalledVoiceCacheKeyUsesVariantVoiceAndPath),
    ("Vocabulary audio cache key", SpeechRuntimeBackendTests.testVocabularyAudioCacheKeySeparatesSpeechSettings),
    ("Speech synthesis error messages", SpeechRuntimeLogicTests.testSpeechSynthesisErrorMessagesAreActionable),
    ("Speech runtime inference failure store", SpeechRuntimeLogicTests.testSpeechRuntimeInferenceFailureStore),
    ("Speech runtime release asset URLs", SpeechRuntimeDownloadTests.testSpeechRuntimeDownloadURLsUseReleaseAssets),
    ("Speech runtime local runtime descriptors", SpeechRuntimeDownloadTests.testSpeechRuntimeLocalRuntimeDescriptors),
    ("Speech runtime local runtime download plans", SpeechRuntimeDownloadTests.testSpeechRuntimeLocalRuntimeDownloadPlans),
    ("Speech runtime local runtime registry", SpeechRuntimeDownloadTests.testSpeechRuntimeLocalRuntimeRegistry),
    ("Speech model manifest checksum validation", SpeechRuntimeManifestTests.testSpeechModelManifestParsingAndChecksumValidation),
    ("Local runtime download manifest asset decoding", SpeechRuntimeDownloadTests.testLocalRuntimeDownloadManifestAssetDecoding),
    ("Speech runtime resume range validation", SpeechRuntimeDownloadTests.testSpeechRuntimeResumeContentRangeValidation),
    ("Speech runtime partial restart policy", SpeechRuntimeDownloadTests.testSpeechRuntimePartialRestartPolicy),
    ("Speech runtime partial metadata validation", SpeechRuntimeDownloadTests.testSpeechRuntimePartialMetadataValidationAndIfRange),
    ("Speech runtime download configuration", SpeechRuntimeDownloadTests.testSpeechRuntimeDownloadConfigurationAndProgressTotals),
    ("Speech model manifest decode fallback", SpeechRuntimeManifestTests.testSpeechModelManifestDecodeFallsBackToBundledManifest),
    ("Speech runtime install disk space policy", SpeechRuntimeDownloadTests.testSpeechRuntimeInstallDiskSpacePolicy),
    ("Bundled speech model manifest parsing", SpeechRuntimeManifestTests.testBundledSpeechModelManifestParses),
    ("Speech runtime availability text", SpeechRuntimeAvailabilityTests.testSpeechRuntimeAvailabilityText),
    ("Local runtime status presenter", SpeechRuntimeAvailabilityTests.testLocalRuntimeStatusPresenter),
    ("Piper runtime resource validation", SpeechRuntimeAvailabilityTests.testPiperRuntimeRequiresPhonemizeResources),
    ("Piper non-default voice validation", SpeechRuntimeAvailabilityTests.testPiperAnyVoiceAcceptsNonDefaultVoice),
    ("Piper model download availability", SpeechRuntimeAvailabilityTests.testPiperModelDownloadMakesBundledRuntimeAvailable),
    ("Speech runtime install state detail", SpeechRuntimeAvailabilityTests.testSpeechRuntimeInstallStateDistinguishesRuntimeAndModel),
    ("Speech runtime health detail", SpeechRuntimeAvailabilityTests.testSpeechRuntimeHealthDistinguishesRuntimeAndModelPaths),
    ("Kokoro model download availability", SpeechRuntimeAvailabilityTests.testKokoroModelDownloadMakesBundledRuntimeAvailable),
    ("Kokoro Mandarin model download availability", SpeechRuntimeAvailabilityTests.testKokoroMandarinModelDownloadMakesBundledRuntimeAvailable),
    ("Piper archive voice validation", SpeechRuntimeDownloadTests.testPiperArchiveValidationRequiresPackagedVoice),
    ("Speech runtime install manifest cache filtering", SpeechRuntimeDownloadTests.testSpeechRuntimeInstallManifestFiltersExternalCachePaths),
    ("Local runtime install manifest compatibility", SpeechRuntimeDownloadTests.testLocalRuntimeInstallManifestCompatibility),
    ("Kokoro cache install transaction", SpeechRuntimeDownloadTests.testKokoroCacheInstallTransactionRollbackAndCommit),
    ("Network error sensitive body formatting", AISettingsLogicTests.testNetworkErrorFormattingSanitizesSensitiveBody),
    ("Network error long body formatting", AISettingsLogicTests.testNetworkErrorFormattingTruncatesLongBody),
    ("AI response parser non-streaming", AISettingsLogicTests.testAIResponseParserParsesNonStreamingResponses),
    ("AI response parser streaming", AISettingsLogicTests.testAIResponseParserParsesStreamingDeltas),
    ("Difficult sentence prompt sections", AISettingsLogicTests.testDifficultSentencePromptContainsRequiredSections),
    ("AI conversation linked history removal", AIConversationContextStoreTests.testLinkedWordHistoryRemovalKeepsSystemMessage),
    ("AI conversation context trimming", AIConversationContextStoreTests.testContextTrimsRecentMessages),
    ("ECDICT SQLite lookup", ECDICTLogicTests.testSQLiteLookupAndMarkdownAnswer),
    ("ECDICT CSV lookup", ECDICTLogicTests.testCSVLookup),
    ("ECDICT lookup key normalization", ECDICTLogicTests.testLookupKeyNormalization),
    ("Answer providers", ECDICTLogicTests.testAnswerProviders),
    ("Embedding key isolation", AISettingsLogicTests.testEmbeddingKeyIsolation),
    ("Embedding legacy key migration", AISettingsLogicTests.testEmbeddingLegacyKeyMigration),
    ("Embedding warmup idle policy", testEmbeddingWarmupIdlePolicy),
    ("Reader entity decoding", EPUBLogicTests.testReaderEntityDecoding),
    ("EPUB text decoding", EPUBLogicTests.testEPUBTextDecoding),
    ("EPUB spine linear parsing", EPUBLogicTests.testEPUBSpineLinearParsing),
    ("EPUB OPF XML parsing", EPUBLogicTests.testEPUBOPFXMLParsing),
    ("EPUB lazy images and safe paths", EPUBLogicTests.testEPUBLazyImagesAndSafePaths),
    ("EPUB unreadable body diagnostics", EPUBLogicTests.testEPUBUnreadableBodyDiagnostics),
    ("EPUB TOC href normalization", EPUBLogicTests.testEPUBTOCHrefNormalization),
    ("EPUB internal links and sanitizing", EPUBLogicTests.testEPUBInternalLinkTargetsAndSanitizing),
    ("Archive paths and ZIP validation", SecurityHardeningTests.testArchivePathsAndZIPValidation),
    ("Runtime archive listing validation", SecurityHardeningTests.testRuntimeArchiveListingValidation),
    ("Temporary resources and content cache identity", SecurityHardeningTests.testTemporaryResourceLifecycleAndContentCacheIdentity),
    ("Web document security policy", SecurityHardeningTests.testWebDocumentSecurityPolicy),
    ("Word record incremental store", VocabularyLogicTests.testWordRecordIncrementalStore),
    ("Word record legacy migration", VocabularyLogicTests.testWordRecordLegacyMigrationDoesNotReviveClearedData),
    ("Page scroll direction", testPageScrollDirection),
    ("PDF paging policy", testPDFPagingPolicy),
    ("Reader session policy", testReaderSessionPolicy),
    ("Reader session PDF anchor", testReaderSessionStorePDFAnchor),
    ("Reader session farthest progress", testReaderSessionStoreFarthestProgress),
    ("Reader session web progress bounds", testReaderSessionStoreWebProgressBounds),
    ("Reader progress formatter", testReaderProgressFormatter),
    ("Vocabulary text policy", VocabularyLogicTests.testVocabularyTextPolicy),
    ("Vocabulary exporter", VocabularyLogicTests.testVocabularyExporter),
    ("Reading note store round trip", ReadingNoteLogicTests.testReadingNoteStoreRoundTrip),
    ("Reading note store unavailable database", ReadingNoteLogicTests.testReadingNoteStoreUnavailableDatabase),
    ("Reading note exporter fallback quote", ReadingNoteLogicTests.testReadingNoteExporterFallbackQuote),
    ("Reading note exporter HTML and scope", ReadingNoteLogicTests.testReadingNoteExporterHTMLAndScope),
    ("Reading note display title uses first markdown line", ReadingNoteLogicTests.testReadingNoteDisplayTitleUsesFirstMarkdownLine),
    ("Reading note list presenter rows", ReadingNoteLogicTests.testReadingNoteListPresenterRows),
    ("Reading note quote soft line breaks", ReadingNoteLogicTests.testReadingNoteQuoteSoftLineBreaks),
    ("Reading note PDF line gaps preserve paragraph breaks", ReadingNoteLogicTests.testReadingNotePDFLineGapsPreserveParagraphBreaks),
    ("Reading note slash command groups", ReadingNoteLogicTests.testReadingNoteSlashCommandGroups),
    ("Reading note templates", ReadingNoteLogicTests.testReadingNoteTemplates),
    ("Reading note slash range policy", ReadingNoteLogicTests.testReadingNoteSlashRangePolicy),
    ("Reading note AI markdown body", ReadingNoteLogicTests.testReadingNoteAIMarkdownBodyStripsFence),
    ("Reading note AI error text", ReadingNoteLogicTests.testReadingNoteAIErrorTextUsesSharedClassifier),
    ("Reading note AI markdown image protector", ReadingNoteLogicTests.testReadingNoteAIMarkdownImageProtector),
    ("Reading note AI document context", ReadingNoteLogicTests.testReadingNoteAIDocumentContext),
    ("Reading note markdown input policy", ReadingNoteLogicTests.testReadingNoteMarkdownInputPolicyRendersInlineStyles),
    ("Reading note markdown render range policy", ReadingNoteLogicTests.testReadingNoteMarkdownRenderRangePolicy),
    ("Markdown block parser parses blocks", ReadingNoteLogicTests.testMarkdownBlockParserParsesBlocks),
    ("Markdown inline parser applies styles", ReadingNoteLogicTests.testMarkdownInlineParserAppliesStyles),
    ("Reading note editing shortcuts", ReadingNoteLogicTests.testReadingNoteEditingShortcutsAcceptControlCopyPaste),
    ("Reading note text replacement policy", ReadingNoteLogicTests.testReadingNoteTextReplacementPolicyRestoresSelection),
    ("Reading note line prefix policy", ReadingNoteLogicTests.testReadingNoteLinePrefixPolicy),
    ("Reading note inline style policy", ReadingNoteLogicTests.testReadingNoteInlineStylePolicyTogglesTrait),
    ("Reading note markdown round trip", ReadingNoteLogicTests.testReadingNoteMarkdownRoundTrip),
    ("Reading note markdown list inline style round trip", ReadingNoteLogicTests.testReadingNoteMarkdownRoundTripPreservesInlineStylesInLists),
    ("Reading note document codec round trip", ReadingNoteLogicTests.testReadingNoteDocumentCodecRoundTrip),
    ("Reading note document appends AI section", ReadingNoteLogicTests.testReadingNoteDocumentAppendsAISection),
    ("Reading note document image markdown", ReadingNoteLogicTests.testReadingNoteDocumentImageMarkdown),
    ("Reading note image markdown round trip with spaced file path", ReadingNoteLogicTests.testReadingNoteImageMarkdownRoundTripWithSpacedFilePath),
    ("Reading note asset store imports image to managed directory", ReadingNoteLogicTests.testReadingNoteAssetStoreImportsImageToManagedDirectory),
    ("Reading note editor state stale AI", ReadingNoteLogicTests.testReadingNoteEditorStateRejectsStaleAIResults),
    ("Reading note AI insertion mode", ReadingNoteLogicTests.testReadingNoteAIInsertionModePlaceholderFlag),
    ("Reader AI context text cleanup", testReaderAIContextTextCleanup),
    ("Reader AI context policy", testReaderAIContextPolicy),
    ("AI response text formatter", testAIResponseTextFormatter),
    ("AI conversation markdown exporter", testAIConversationMarkdownExporter),
    ("Embedding action policy", testEmbeddingActionPolicy),
    ("Selection toolbar configuration", VocabularyLogicTests.testSelectionToolbarConfiguration),
    ("Vocabulary review display record loader", VocabularyLogicTests.testVocabularyReviewDisplayRecordLoaderLoadsOnlyCurrentRecord),
    ("Reading context snapshot", testReadingContextSnapshot),
    ("Reader focused selection priority", testReaderFocusedSelectionPriority),
    ("Reader AI source matcher", testReaderAISourceMatcher),
    ("PDF read-aloud chrome filter", testPDFReadAloudChromeFilterLearnsRepeatedEdgeLines),
    ("Paper structure detector", testPaperStructureDetectorFindsStableSectionHeadings),
    ("Paper structure detector weak signals", testPaperStructureDetectorRejectsWeakSectionSignals),
    ("Captured page scroll guard", testCapturedPageScrollGuard),
    ("PDF brightness policy", testPDFBrightnessPolicy),
    ("Debounced task", testDebouncedTask),
    ("Speech text normalization", testSpeechTextPolicyNormalization),
    ("Speech text English candidate", testSpeechTextPolicyEnglishCandidate),
    ("Speech text segments", testSpeechTextPolicySegments),
    ("Read-aloud text matcher", testReadAloudTextMatcher),
    ("Read-aloud manual advance key policy", testReadAloudManualAdvanceKeyPolicy),
    ("Read-aloud playback phase", testReadAloudPlaybackPhase),
    ("Kokoro worker response reader", testKokoroWorkerResponseReader),
    ("Kokoro worker response partial lines", testKokoroWorkerResponseReaderBuffersPartialLines)
]

@main
private struct LogicTestRunner {
    static func main() {
        var failures: [String] = []
        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                failures.append("FAIL \(name): \(error)")
            }
        }

        if failures.isEmpty {
            print("All \(tests.count) logic tests passed.")
        } else {
            for failure in failures {
                print(failure)
            }
            exit(1)
        }
    }
}

# TTS And Read Aloud

Use this page when changing local speech playback, read-aloud highlights, or downloadable TTS model runtimes.

## Runtime Shape

```text
ReaderWindowController+ReadAloud
  -> KittenTTSPlayer
     -> SpeechRuntimeResourceManager
        -> KittenTTS runtime
        -> Kokoro Core ML runtime
     -> AVAudioPlayer
  -> ReaderWindowController+TTSProgress
```

Short vocabulary and AI-panel speech can fall back to `NSSpeechSynthesizer` through `SpeechUtteranceFactory` when the local model path is not appropriate.

## Main Files

- `mac-app/KittenTTSPlayer.swift`: central speech coordinator. It chooses the installed runtime, segments text, manages generated WAV files, controls playback, and posts progress notifications.
- `mac-app/SpeechRuntimeResourceManager.swift`: install detection, download URLs, model sizes, runtime compatibility, pause/resume/cancel state, and cleanup.
- `mac-app/RuntimeDownload.swift`: URLSession download implementation, progress reporting, resume data, and HTTP error handling.
- `mac-app/AISettingsPanelController+Speech.swift`: settings actions for selecting, downloading, pausing, canceling, deleting, and warning about incompatible runtimes.
- `mac-app/AISettingsPanelController+Build.swift`: visible read-aloud settings rows, model picker, status labels, buttons, and progress indicators.
- `mac-app/ReaderWindowController+ReadAloud.swift`: document-level read-aloud entry points for PDF and WebKit-backed EPUB/DOCX content.
- `mac-app/ReaderWindowController+TTSProgress.swift`: active segment underline/highlight updates while speech is playing.
- `mac-app/AIChatPanel+Actions.swift`: speak selected AI text, with local TTS when possible and system speech fallback.
- `mac-app/ReaderWindowController+VocabularyActions.swift`: vocabulary pronunciation, interruption behavior, and fallback speech.
- `mac-app/SpeechUtteranceFactory.swift`: common system voice utterance settings.

## Runtime Rules

- KittenTTS is the default local runtime target for macOS 12 and later.
- Kokoro can be downloaded on older macOS versions, but it requires macOS 14 or later to run. The settings UI shows a compatibility warning before download on unsupported systems.
- `SpeechRuntimeResourceManager.isInstalled(_:)` only reports a runtime as selectable when the files are present and the current macOS version can run it.
- `SpeechRuntimeResourceManager.installedRuntime(preferredID:)` is the runtime selection gate used by playback code.
- Download status text is user-facing; keep it aligned with the actual install and compatibility checks.

## Packaging And Release

- `scripts/build_espeak_ng_runtime.sh`: builds the lower deployment target `espeak-ng` and `pcaudiolib` runtime used by KittenTTS.
- `scripts/build_app.sh`: copies speech runtimes into the app bundle and verifies bundled runtime layout.
- `scripts/package_speech_runtimes.sh`: packages downloadable TTS runtime archives.
- `scripts/publish_release.sh`: uploads release packages and TTS runtime assets, then updates Sparkle appcast data.

When changing bundled native runtime binaries, verify their minimum macOS version with `vtool` or `otool` before publishing.

## Checks

```sh
./tests/run.sh
./scripts/build_app.sh
./scripts/check.sh --no-build
```

For download behavior, test at least these states:

- runtime absent
- runtime downloading
- runtime paused
- runtime installed and compatible
- runtime downloaded but incompatible with the current macOS version

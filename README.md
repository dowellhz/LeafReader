<p align="center">
  <img src="assets/leaf-reader-icon.png" alt="Leaf Reader icon" width="128">
</p>

# Leaf Reader

<p align="center">
  <a href="#中文">中文</a> |
  <a href="#english">English</a>
</p>

## 中文

Leaf Reader 是一个原生 macOS 文档阅读器，支持 PDF、EPUB 和 DOCX。它面向长文档阅读、学习和批注场景，提供阅读进度恢复、文档搜索、浅色/护眼/深色主题、AI 问答、选中文本翻译/解释/总结、背单词和本地朗读。

官网：<https://leafreader.space/>

### 截图

![Leaf Reader 亮色模式单词学习](assets/reader-light-ai-word.png?v=20260524-shadow)

![Leaf Reader 书架](assets/reader-bookshelf.png?v=20260524-shadow)

![Leaf Reader 设置](assets/reader-settings.png?v=20260524-shadow)

![Leaf Reader 深色模式设置](assets/reader-dark-ai.png?v=20260524-shadow)

![Leaf Reader 背单词复习](assets/reader-dark-vocabulary.png?v=20260524-shadow)

### 下载

[下载 Leaf Reader 1.6.5 pkg 安装包](https://github.com/dowellhz/LeafReader/releases/download/v1.6.5/LeafReader-1.6.5.pkg)

### 系统要求

- macOS 12.0 Monterey 或更高版本。
- 阅读器支持 Apple Silicon 和 Intel Mac；本地 TTS runtime 当前仅支持 Apple Silicon。
- AI 功能需要用户自行配置模型服务和 API Key；普通阅读不需要。
- KittenTTS 和 Piper 本地朗读支持 Apple Silicon Mac 上的 macOS 12.0 Monterey 或更高版本。
- Kokoro 本地朗读需要 Apple Silicon Mac 上的 macOS 14.0 或更高版本。

### 主要功能

- 打开本地 PDF、EPUB、DOCX 文档，并自动恢复阅读位置。
- 支持文档搜索、PDF 翻页、书架、最近阅读、浅色/护眼/深色主题。
- 选中文本后可让 AI 解释、总结、翻译或继续追问上下文。
- 支持保存单词、复习新词、导出词表。
- 支持 KittenTTS 和 Kokoro 本地朗读；短词和短句可回退到 macOS 系统语音。
- 文档保存在本机；只有使用 AI 功能时，相关文本才会发送到用户配置的模型服务。

### 可选朗读模型

Leaf Reader 可以使用 [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml)、[kitten_tts_rs](https://github.com/second-state/kitten_tts_rs) 或 Piper 进行本地朗读。Kokoro 提供英文和中文声音，KittenTTS 和 Piper 用于英文朗读。小型运行时已经随安装包提供，大模型文件按需下载。打开“设置 -> AI 分析 -> 朗读”即可下载 Kokoro、KittenTTS 或 Piper。

朗读模型优先级会自动处理：KittenTTS 优先，其次 Kokoro。短词或短句会直接使用 Apple 系统语音。

语音模型下载目前复用稳定的 `v1.5.10` 语音资源发布：

- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kokoro-coreml-macos-arm64.tar.gz`
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kitten-tts-rs-macos-arm64.tar.gz`
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/piper-tts-macos-arm64.tar.gz`

常规应用版本会复用这些模型文件。只有模型文件变化时才需要重新发布语音模型归档，并同步更新 `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag`。

### 更新记录

#### 1.6.6

- 降低 Piper runtime 的最低 macOS 标记到 macOS 12.0，并加强发布前 bundle 校验。
- 修复朗读模型状态判断，区分缺少运行时和缺少模型。
- 同步本地与远端语音模型清单，并明确本地 TTS runtime 的 Apple Silicon 要求。

#### 1.6.5

- 修复安装版 Piper 朗读 runtime 缺少动态库搜索路径导致启动失败的问题。
- 细分朗读错误提示，区分模型未下载、中文内容需要 Kokoro，以及 runtime 启动失败。
- 发布检查增加 Piper runtime bundle 校验，避免缺失 `LC_RPATH` 的包进入发布流程。

#### 1.6.4

- 增加 Piper 作为本地英文朗读模型选项，并随安装包提供 Piper runtime。
- 朗读浮动控制器增加停止和设置入口。
- 优化朗读模型下载列表、Piper 语速处理和发布资源上传流程。

#### 1.6.3

- 朗读浮动播放器增加“下一页”按钮，可直接接续朗读下一页内容。
- 修复 PDF 双页模式下朗读从左页跳到右页时不应翻到下一屏的问题。
- 底部工具栏“书架”和“背单词”按钮增加与主题一致的 SF Symbol 图标。

#### 1.6.2

- 增加朗读时的浮动播放器，支持上一句、暂停/继续、下一句，以及自动/手动接续模式。
- 优化朗读队列，点击下一句会立即停止当前句并播放下一句，手动模式每次只播放一句。
- 保留最近两句 wav 缓存，让上一句回退更流畅。
- 修复朗读浮动播放器与 PDF 单词标记、AI 提示气泡和页面点击之间的层级/点击冲突。

#### 1.6.1

- 缩减安装包内置语音资源，只保留 KittenTTS 所需的 espeak 英文字典。
- 删除重复 Kokoro 英文声音，保留 Bella、Heart、Adam、Emma、George。
- 保持 KittenTTS 和 Kokoro 本地朗读在更小的 runtime 资源下正常工作。

#### 1.6.0

- 使用统一主题色重新打磨阅读器、AI 聊天、设置、最近文档和词汇界面。
- 给选中文本浮动工具栏动作增加 SF Symbol 图标，并让工具栏布局更紧凑。
- 改进 AI 聊天气泡持久化、关联单词处理和跨阅读会话的来源标注。
- 增强 embedding 在回填、重建和切换文档时的生命周期与状态处理。
- 优化词汇复习/列表导航和最近文档清理流程。

更早版本见 [GitHub Releases](https://github.com/dowellhz/LeafReader/releases)。

### 许可证

Leaf Reader 使用 [Apache License 2.0](LICENSE) 许可发布。

## English

Leaf Reader is a native macOS reader for PDF, EPUB, and DOCX documents. It is built with Swift, PDFKit, and WebKit, and focuses on a quiet reading experience with fast navigation, document search, reading progress restore, light and dark reader themes, and an optional AI panel for working with selected passages.

Website: <https://leafreader.space/>

### Screenshots

![Leaf Reader word learning in light mode](assets/reader-light-ai-word.png?v=20260524-shadow)

![Leaf Reader bookshelf](assets/reader-bookshelf.png?v=20260524-shadow)

![Leaf Reader settings](assets/reader-settings.png?v=20260524-shadow)

![Leaf Reader settings in dark mode](assets/reader-dark-ai.png?v=20260524-shadow)

![Leaf Reader vocabulary review](assets/reader-dark-vocabulary.png?v=20260524-shadow)

### Download

[Leaf Reader 1.6.5 pkg installer](https://github.com/dowellhz/LeafReader/releases/download/v1.6.5/LeafReader-1.6.5.pkg)

### System Requirements

- macOS 12.0 Monterey or later.
- The reader supports Apple Silicon and Intel Mac; local TTS runtimes currently require Apple Silicon.
- An API key is optional and only needed for AI features.
- KittenTTS and Piper local speech support macOS 12.0 Monterey or later on Apple Silicon Macs.
- Kokoro local speech requires macOS 14.0 or later on Apple Silicon Macs.

### Highlights

- Open local PDF, EPUB, and DOCX files in one macOS app.
- Restore the last opened document, page, zoom level, and reading position.
- Navigate PDFs with toolbar controls, keyboard paging, scroll paging, and direct page-number entry.
- Search documents with `Command+F`, next and previous result controls, and visible result positioning.
- Switch between light and dark reader themes for the document area, search overlay, recent files panel, and AI chat panel.
- Select text and ask the built-in AI assistant to explain, summarize, or translate passages.
- Read selected English or Chinese text with optional downloadable Kokoro or KittenTTS output where supported; otherwise Leaf Reader falls back to macOS system voices.
- Keep documents local; AI requests are only sent when the assistant is used with the configured API key.

### Optional Speech Runtimes

Leaf Reader can use [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml), [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs), or Piper for local text-to-speech. Kokoro provides English and Chinese voices; KittenTTS and Piper are used for English read aloud. Small speech runtime executables are bundled in the installer; large model files are downloaded on demand. Open Settings -> AI Analysis -> Speech to download Kokoro, KittenTTS, or Piper.

Runtime priority is automatic: KittenTTS first, then Kokoro. Short word or phrase selections use Apple TTS directly.

Speech model downloads currently point to the stable `v1.5.10` speech asset release:

- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kokoro-coreml-macos-arm64.tar.gz`
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kitten-tts-rs-macos-arm64.tar.gz`
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/piper-tts-macos-arm64.tar.gz`

Regular app releases reuse those files. Regenerated speech archives should only be published when model files change, then `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag` should be updated to the new asset tag.

### Changelog

#### 1.6.6

- Lowered the Piper runtime minimum macOS marker to macOS 12.0 and strengthened release-time bundle checks.
- Improved speech runtime status detection so missing runtimes and missing models are reported separately.
- Synced local and remote speech model manifests and clarified the Apple Silicon requirement for local TTS runtimes.

#### 1.6.5

- Fixed the installed Piper runtime so its bundled dynamic libraries are found at launch.
- Split read-aloud error messages between missing models, Chinese text requiring Kokoro, and runtime launch failures.
- Added a release-time Piper bundle check so packages missing the required `LC_RPATH` fail before publishing.

#### 1.6.4

- Added Piper as a local English read-aloud model option with bundled runtime support.
- Improved read-aloud controls with stop and settings actions in the floating player.
- Tightened TTS model download rows, Piper speed handling, and release asset publishing.

#### 1.6.3

- Added a next-page control to the floating read-aloud player.
- Fixed PDF two-page read-aloud navigation so moving from the left page to the visible right page does not turn to the next spread.
- Added theme-matched SF Symbol icons to the bottom toolbar Shelf and Vocab buttons.

#### 1.6.2

- Added an in-reader floating read-aloud controller with previous, pause/resume, next, and auto/manual advance modes.
- Improved read-aloud queue behavior so Next immediately stops the current sentence and starts the next one, while manual mode plays one sentence at a time.
- Kept the two most recent wav segments cached to make Previous sentence playback faster.
- Fixed layering and click handling conflicts between the floating player, PDF word highlights, AI hint bubbles, and page clicks.

#### 1.6.1

- Reduced the bundled speech footprint by keeping only the espeak English dictionary needed by KittenTTS.
- Trimmed duplicate Kokoro English voices while keeping Bella, Heart, Adam, Emma, and George available.
- Kept KittenTTS and Kokoro local playback working with the smaller bundled runtime resources.

#### 1.6.0

- Refined the reader, AI chat, settings, recent documents, and vocabulary surfaces with a shared theme palette.
- Added SF Symbol icons to the selected-text floating toolbar actions and tightened the toolbar layout.
- Improved AI chat bubble persistence, linked word handling, and source annotations across reading sessions.
- Made embedding lifecycle/status handling more resilient during backfill, rebuild, and document changes.
- Polished vocabulary review/list navigation and recent document cleanup flows.

Earlier versions are listed in [GitHub Releases](https://github.com/dowellhz/LeafReader/releases).

### License

Leaf Reader is licensed under the [Apache License 2.0](LICENSE).

## What's New in 1.6.6

- Lowered the Piper runtime minimum macOS marker to macOS 12.0 and added checks to prevent mismatched bundles.
- Improved speech model status text for missing runtime versus missing model cases.
- Synced speech model manifests and clarified local TTS compatibility.

## What's New in 1.6.5

- Fixed Piper read-aloud startup in installed builds by bundling the required dynamic library search path.
- Improved read-aloud error messages for missing models, Chinese-only Kokoro requirements, and runtime launch failures.
- Added release checks that catch malformed Piper runtime bundles before publishing.

## What's New in 1.6.4

- Added Piper as a local English read-aloud model option with bundled runtime support.
- Improved read-aloud controls with stop and settings actions in the floating player.
- Tightened TTS model download rows, Piper speed handling, and release asset publishing.

## What's New in 1.6.3

- The floating read-aloud player now includes a next-page button.
- In PDF two-page mode, next-page read-aloud moves from the left page to the visible right page without turning the spread.
- The bottom toolbar Shelf and Vocab buttons now include SF Symbol icons.

## Development

### Requirements

- macOS 12.0 Monterey or later.
- Swift toolchain with Cocoa, PDFKit, WebKit, and CryptoKit frameworks.
- Sparkle for release builds.

### Build From Source

Install Sparkle first:

```sh
brew install --cask sparkle
```

Build the macOS 12-compatible KittenTTS `espeak-ng` helper runtime when the speech runtime dependencies change:

```sh
brew install autoconf automake libtool pkgconf
./scripts/build_espeak_ng_runtime.sh
```

Build and run the app:

```sh
./scripts/build_app.sh
open "Leaf Reader.app"
```

### Tests

Run lightweight logic regression tests:

```sh
./tests/run.sh
```

Run the full local pre-commit check:

```sh
./scripts/check.sh
```

### Speech Model Packages

Generate speech model packages with:

```sh
./scripts/package_speech_models.sh
```

The packaging script also writes `docs/tts/speech-models-manifest.json` with each asset's file size and SHA256 digest. Publish with `--with-speech-models` only when the model archives change.

### Project Layout

- `Leaf Reader.app` - generated macOS application bundle, ignored by git.
- `mac-app/*.swift` - native Swift source code.
- `tests/` - lightweight Swift logic regression tests.
- `docs/` - GitHub Pages site, manual, and Sparkle update feed.
- `assets/` - README icon and screenshots.
- `release/` - local release artifacts when generated.

### Code Wiki

Developer notes live in `docs/wiki/`:

- [Code Wiki index](docs/wiki/index.md)
- [Code Map](docs/wiki/code-map.md)

Regenerate the code map after larger refactors:

```sh
./scripts/generate_code_wiki.sh
```

### Release

Current version: `1.6.5`

Git tag: `v1.6.5`

Latest installer:

[Leaf Reader-1.6.5.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.6.5/LeafReader-1.6.5.pkg)

Local release package path:

`release/1.6.5/LeafReader-1.6.3.pkg`

Build the signed release package without publishing:

```sh
./scripts/release_pkg.sh 1.6.5
```

Run the full publish flow from a clean working tree:

```sh
./scripts/publish_release.sh 1.6.5
```

The publish script runs tests, builds/signs/notarizes the pkg, commits version/appcast changes, tags the release, pushes `main` and the tag, creates the GitHub Release, uploads the pkg, and verifies the download URL. Pass `--with-speech-models` only when publishing changed speech model archives in `docs/tts/`.

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- Automatic updates use Sparkle and the public EdDSA key embedded in `mac-app/Info.plist`.
- PDF rendering uses PDFKit.
- EPUB and DOCX rendering uses WebKit. DOCX support is optimized for readable text extraction rather than exact Word layout fidelity.
- Search selections are kept separate from AI passage selection so search navigation does not accidentally populate the assistant.
- AI requests use the model, endpoint, language, and API key configured locally in the settings panel.

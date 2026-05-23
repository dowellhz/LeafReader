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

官网会根据浏览器语言自动显示中文或英文，也可以在页面右上角手动切换：<https://leafreader.space/>

### 截图

![Leaf Reader 亮色模式单词学习](assets/reader-light-ai-word.png)

![Leaf Reader 书架](assets/reader-bookshelf.png)

![Leaf Reader 设置](assets/reader-settings.png)

![Leaf Reader 深色模式 AI 阅读](assets/reader-dark-ai.png)

![Leaf Reader 背单词复习](assets/reader-dark-vocabulary.png)

### 下载

[下载 Leaf Reader 1.6.1 pkg 安装包](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

### 系统要求

- macOS 12.0 Monterey 或更高版本。
- 支持 Apple Silicon 和 Intel Mac。
- AI 功能需要用户自行配置模型服务和 API Key；普通阅读不需要。
- KittenTTS 本地朗读支持 macOS 12.0 Monterey 或更高版本。
- Kokoro 本地朗读需要 macOS 14.0 或更高版本。

### 主要功能

- 打开本地 PDF、EPUB、DOCX 文档，并自动恢复阅读位置。
- 支持文档搜索、PDF 翻页、书架、最近阅读、浅色/护眼/深色主题。
- 选中文本后可让 AI 解释、总结、翻译或继续追问上下文。
- 支持保存单词、复习新词、导出词表。
- 支持 KittenTTS 和 Kokoro 本地朗读；短词和短句可回退到 macOS 系统语音。
- 文档保存在本机；只有使用 AI 功能时，相关文本才会发送到用户配置的模型服务。

### 可选朗读模型

Leaf Reader 可以使用 [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) 或 [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs) 进行本地朗读。Kokoro 提供英文和中文声音，KittenTTS 用于英文朗读。小型运行时已经随安装包提供，大模型文件按需下载。打开“设置 -> AI 分析 -> 朗读”即可下载 Kokoro 或 KittenTTS。

朗读模型优先级会自动处理：KittenTTS 优先，其次 Kokoro。短词或短句会直接使用 Apple 系统语音。

语音模型下载目前复用稳定的 `v1.5.10` 语音资源发布：

- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kokoro-coreml-macos-arm64.tar.gz`
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kitten-tts-rs-macos-arm64.tar.gz`

常规应用版本会复用这些模型文件。只有模型文件变化时才需要重新发布语音模型归档，并同步更新 `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag`。

### 更新记录

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

The website automatically follows the browser language and also provides a manual Chinese/English switch in the header: <https://leafreader.space/>

### Screenshots

![Leaf Reader word learning in light mode](assets/reader-light-ai-word.png)

![Leaf Reader bookshelf](assets/reader-bookshelf.png)

![Leaf Reader settings](assets/reader-settings.png)

![Leaf Reader passage explanation in dark mode](assets/reader-dark-ai.png)

![Leaf Reader vocabulary review](assets/reader-dark-vocabulary.png)

### Download

[Leaf Reader 1.6.1 pkg installer](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

### System Requirements

- macOS 12.0 Monterey or later.
- Apple Silicon or Intel Mac.
- An API key is optional and only needed for AI features.
- KittenTTS local speech supports macOS 12.0 Monterey or later.
- Kokoro local speech requires macOS 14.0 or later.

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

Leaf Reader can use [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) or [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs) for local text-to-speech. Kokoro provides English and Chinese voices; KittenTTS is used for English read aloud. Small speech runtime executables are bundled in the installer; large model files are downloaded on demand. Open Settings -> AI Analysis -> Speech to download Kokoro or KittenTTS.

Runtime priority is automatic: KittenTTS first, then Kokoro. Short word or phrase selections use Apple TTS directly.

Speech model downloads currently point to the stable `v1.5.10` speech asset release:

- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kokoro-coreml-macos-arm64.tar.gz`
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kitten-tts-rs-macos-arm64.tar.gz`

Regular app releases reuse those files. Regenerated speech archives should only be published when model files change, then `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag` should be updated to the new asset tag.

### Changelog

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

Current version: `1.6.1`

Git tag: `v1.6.1`

Latest installer:

[Leaf Reader-1.6.1.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

Run the full publish flow from a clean working tree:

```sh
./scripts/publish_release.sh 1.6.1
```

The publish script runs tests, builds/signs/notarizes the pkg, commits version/appcast changes, tags the release, pushes `main` and the tag, creates the GitHub Release, uploads the pkg, and verifies the download URL. Pass `--with-speech-models` only when publishing changed speech model archives in `docs/tts/`.

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- Automatic updates use Sparkle and the public EdDSA key embedded in `mac-app/Info.plist`.
- PDF rendering uses PDFKit.
- EPUB and DOCX rendering uses WebKit. DOCX support is optimized for readable text extraction rather than exact Word layout fidelity.
- Search selections are kept separate from AI passage selection so search navigation does not accidentally populate the assistant.
- AI requests use the model, endpoint, language, and API key configured locally in the settings panel.

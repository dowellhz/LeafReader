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

[下载 Leaf Reader 1.7.5 pkg 安装包](https://github.com/dowellhz/LeafReader/releases/download/v1.7.5/LeafReader-1.7.5.pkg)

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
- 支持 KittenTTS、Piper 和 Kokoro 本地朗读；短词和短句可回退到 macOS 系统语音。
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

#### 1.7.7

- 新增难句解析入口：阅读笔记选中文本和正文选中句子后都可以直接请求 AI 拆解难句。
- 难句解析会按句子结构、主谓宾/从句/修饰关系、逐层翻译、常见表达和写法原因输出。
- 整理选中文本 AI 动作的共用流程，减少总结、翻译和难句解析之间的重复逻辑。

#### 1.7.6

- 改进 AI 对话导出，支持 Markdown、HTML 和 PDF，并让导出按钮跟随当前主题配色。
- 合并阅读笔记导出流程到系统保存面板，隐藏标签栏，并把范围和文件类型放在同一个选择区域。
- 修复 AI 对话和阅读笔记导出的 HTML/PDF Markdown 渲染，标题、列表和 `**加粗**` 等内容会显示为实际样式。
- 将阅读笔记导出入口改名为“导出笔记”，并整理导出相关代码和测试。

#### 1.7.5

- 新增阅读笔记导出选项，支持 Markdown、HTML 和 PDF，并可只导出收藏笔记。
- 改进 PDF 朗读分段匹配，重复文本和跨页/跨句朗读时能更准确地高亮当前句子。
- 修复 PDF 断行连字符单词保存和高亮，例如 `Nine-\ntenths` 会作为 `Nine-tenths` 处理。
- 收窄 PDF 单词下划线范围，避免跨行选词时生成过长下划线。
- 更新代码索引和相关逻辑测试。

#### 1.7.4

- 优化单词查询路径：AI 请求时不再同步触发本地词典慢查询，本地词典 metadata 改为后台补齐，减少浮动菜单点词时的卡顿。
- 精简 ECDICT 查询策略：多词选区不再检索本地词典，未命中时不做全表扫描，检索依据会跟随主词条删除。
- 改进朗读浮动控制：上一条、下一条、重播和快捷键会聚焦到当前朗读句子所在页面与位置。
- 放大选中单词和句子的浮动菜单文字，让解释、总结、翻译等操作更容易点击和阅读。
- 整理 AI 气泡、单词持久化、朗读导航和词典查询相关代码，移除临时性能监控逻辑。

#### 1.7.3

- 阅读笔记支持图片资源持久化，插入图片会保存到应用资源目录，重新打开笔记后不再只剩文件名或丢失图片。
- 改进阅读笔记的 AI 整理流程：向 AI 发送内容时保留图片占位符，整理结果会自动还原图片，避免图片在改写、总结或润色后消失。
- 重构阅读笔记 Markdown 渲染、序列化、样式策略和 slash 范围处理，减少从富文本反推 Markdown 带来的样式漂移。
- 放大阅读笔记窗口、正文、元信息和工具栏相关字号，并修复图片按钮可能卡住的问题。
- 优化朗读选区上下文：没有普通选区时，AI 总结、翻译和问问题会使用当前朗读选中的句子；朗读工具条增加当前句重播按钮。
- 改进单词查询：AI 结果会复用本地词典 Tags，标签展示更紧凑；网络不可用或模型不可达时更可靠地回退到本地词典。
- 统一历史单词标注和新标注的下划线颜色，并修复朗读选中句子解析后缺少下划线标记的问题。
- 调整 AI 气泡正文和标题字号，并整理 AI 面板、词汇、朗读和阅读笔记相关代码边界。

#### 1.7.2

- 改进阅读笔记：支持保存按钮、复制/粘贴快捷键，并修复重新打开后样式和字数统计不同步的问题。
- 修复朗读手动/自动接续和下一页流程中的状态遗漏，让 PDF/Web 朗读翻页更稳定。
- 整理阅读笔记、朗读、文档、AI 和 embedding 状态结构，降低后续维护风险。

#### 1.7.1

- 增强离线和未配置模型时的选词体验：本地 ECDICT 查询、朗读、复制和模型设置入口的状态更清晰。
- 优化背单词流程，默认词频优先，并避免一次性查询整批单词导致卡顿。
- 整理网络/模型状态、浮动窗口、本地词典和复习卡片加载结构。

#### 1.7.0

- 增加阅读笔记入口，并改进笔记编辑、Ask AI、粘贴和右键菜单行为。
- 优化朗读控制状态、停止图标、语速滑块和浮动播放器布局。
- 增加词汇复习优先级选项，并整理词汇复习/列表结构，让每日复习更稳定。

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

第三方朗读模型和运行时版权归各自项目所有：

- [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) / Kokoro 模型：Apache License 2.0。
- [KittenTTS](https://github.com/KittenML/KittenTTS) 与 [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs)：KittenTTS 模型为 Apache License 2.0；Rust runtime 版权归 `kitten_tts_rs` 项目贡献者所有。
- [Piper](https://github.com/rhasspy/piper)：MIT License；Piper 语音模型资源版权和许可遵循上游模型包随附的元数据。

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

[Leaf Reader 1.7.8 pkg installer](https://github.com/dowellhz/LeafReader/releases/download/v1.7.8/LeafReader-1.7.8.pkg)

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
- Read selected English or Chinese text with optional downloadable KittenTTS, Piper, or Kokoro output where supported; otherwise Leaf Reader falls back to macOS system voices.
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

#### 1.7.3

- Made Reading Note images persistent: inserted images are copied into the app's Reading Note asset store and reopen correctly instead of degrading to filenames.
- Improved AI organize/polish flows for Reading Notes by protecting image placeholders before sending Markdown to AI and restoring them after the response.
- Refactored Reading Note Markdown rendering, serialization, inline style policy, slash ranges, and line-prefix handling to reduce rich-text-to-Markdown drift.
- Enlarged the Reading Note window, body text, metadata text, and toolbar sizing, and fixed the image picker action that could freeze the note editor.
- Improved read-aloud context fallback so Summary, Translate, and Ask use the currently spoken sentence when there is no explicit text selection; added replay for the current read-aloud segment.
- Improved vocabulary lookup by reusing local dictionary tags in AI word answers, compacting tag display, and falling back to the local dictionary more reliably when the model is unavailable.
- Kept historical and newly-created vocabulary underline colors consistent, including read-aloud sentence parsing highlights.
- Adjusted AI bubble body/header font sizing and continued splitting AI panel, vocabulary, read-aloud, and Reading Note code into clearer boundaries.

#### 1.7.2

- Improved Reading Notes with a save button, copy/paste shortcuts, and fixes for reopened styling and word-count refresh.
- Fixed read-aloud continuation edge cases across manual/automatic advance and next-page flows for more reliable PDF/Web playback.
- Refactored Reading Notes, read-aloud, document, AI, and embedding state boundaries to reduce maintenance risk.

#### 1.7.1

- Improved selection behavior when offline or when no model API key is configured, with clearer local ECDICT, speech, copy, and model-settings states.
- Refined vocabulary review with frequency-first ordering by default and current-card dictionary lookup to avoid batch lookup stalls.
- Cleaned up network/model capability, selection toolbar, local dictionary, and review-card loading boundaries.

#### 1.7.0

- Added Reading Notes access from the reader toolbar and refined note editing, Ask AI, paste, and context-menu behavior.
- Improved read-aloud controls with clearer toolbar states, stop icons, a speed slider, and better floating control layout.
- Added vocabulary review priority options and tightened the vocabulary review/list architecture for more reliable daily review.

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

Third-party speech models and runtimes remain copyrighted by their respective projects:

- [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) / Kokoro model: Apache License 2.0.
- [KittenTTS](https://github.com/KittenML/KittenTTS) and [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs): KittenTTS model under Apache License 2.0; Rust runtime copyright belongs to the `kitten_tts_rs` project contributors.
- [Piper](https://github.com/rhasspy/piper): MIT License; Piper voice model assets follow the metadata shipped with the upstream model package.

## What's New in 1.7.8

- Improved reader theme coverage so chrome, toolbar, search, bookshelf, vocabulary, and AI surfaces consistently follow white, eye-care, and dark themes.
- Tightened release and documentation checks: local checks now build the manual in a temporary directory to avoid noisy generated HTML diffs.
- Cleaned up speech runtime release maintenance by removing obsolete runtime download wrappers and splitting Piper worker helpers into focused support code.
- Added regression coverage for theme palette colors and kept UI theme scanning warning-free.

## What's New in 1.7.7

- Added a Difficult Sentence action for selected text in Reading Notes and for selected sentences in the main reader.
- Difficult sentence analysis now asks AI for sentence structure, subject/verb/object and clauses, layered translation, common expressions, and why the sentence is written that way.
- Refactored selected-text AI action handling to share the common summary, translation, and difficult sentence request flow.

## What's New in 1.7.6

- AI conversation export now supports Markdown, HTML, and PDF, and the export button follows the current theme.
- Reading Notes export now uses one save panel with scope and file type selectors, without the macOS tags field.
- HTML and PDF exports render Markdown content instead of showing raw syntax, including headings, lists, and `**bold**` text.
- Renamed the Reading Notes export action to Export Notes and cleaned up shared export rendering coverage.

## What's New in 1.7.5

- Added richer Reading Notes export options for Markdown, HTML, and PDF, including favorite-only export scope.
- Improved PDF read-aloud segment matching so repeated text and spoken sentence highlights land on the intended location.
- Fixed PDF line-broken hyphenated vocabulary words, so selections such as `Nine-\ntenths` are saved and queried as `Nine-tenths`.
- Tightened PDF vocabulary underline bounds to avoid overly long lines when a word crosses a line break.
- Updated code indexes and focused logic coverage for the new export and vocabulary behavior.

## What's New in 1.7.4

- Faster vocabulary lookup from the floating selection menu: AI requests no longer block on slow local dictionary work, and dictionary metadata is filled in asynchronously.
- Tighter ECDICT behavior: multi-word selections skip local dictionary lookup, misses no longer fall back to table scans, and lookup keys are deleted with their main entries.
- Read-aloud navigation now focuses the active spoken sentence when using previous, next, replay, or their keyboard shortcuts.
- Selection floating menu text is larger for word and sentence actions.
- Cleaned up AI bubble, vocabulary persistence, read-aloud navigation, and dictionary lookup code, including removal of temporary performance tracing.

## What's New in 1.7.3

- Reading Note images now persist through save, reopen, and AI organize/polish flows.
- Markdown handling in Reading Notes is cleaner and more stable, with dedicated parsers, render policies, image protection, and asset storage.
- Read-aloud now supports replaying the current segment and can provide the spoken sentence as AI context when no other text is selected.
- Vocabulary AI answers reuse local dictionary tags, show tags more compactly, and fall back to local dictionary data more reliably.
- AI bubbles, Reading Note typography, underline colors, and related UI details were polished for consistency.

## What's New in 1.7.2

- Improved Reading Notes with a save button, copy/paste shortcuts, and fixes for reopened styling and word-count refresh.
- Fixed read-aloud continuation edge cases across manual/automatic advance and next-page flows for more reliable PDF/Web playback.
- Refactored Reading Notes, read-aloud, document, AI, and embedding state boundaries to reduce maintenance risk.

## What's New in 1.7.1

- Improved offline and unconfigured-model selection behavior with local ECDICT lookup, speech, copy, and model settings states.
- Made vocabulary review default to frequency-first ordering and kept dictionary lookup scoped to the current card.
- Refactored network/model capability checks, selection toolbar configuration, local dictionary lookup, and review-card loading.

## What's New in 1.7.0

- Added easier access to Reading Notes, with improved note editing, Ask AI prompts, paste handling, and disabled note-editor context menus.
- Improved read-aloud controls with clearer loading/pause/stop icons, a speech-speed slider, and better floating player layout.
- Added vocabulary review priority choices and refined the review UI, scoring, and speech playback internals.

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

Current version: `1.7.8`

Git tag: `v1.7.8`

Latest installer:

[Leaf Reader-1.7.8.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.7.8/LeafReader-1.7.8.pkg)

Local release package path:

`release/1.7.8/LeafReader-1.7.8.pkg`

Build the signed release package without publishing:

```sh
./scripts/release_pkg.sh 1.7.8
```

Run the full publish flow from a clean working tree:

```sh
./scripts/publish_release.sh 1.7.8
```

The publish script runs tests, builds/signs/notarizes the pkg, smoke-tests the package payload, reports speech runtime size, commits version/appcast changes, tags the release, pushes `main` and the tag, creates the GitHub Release, uploads the pkg, and verifies the download URL. Pass `--with-speech-models` only when publishing changed speech model archives in `docs/tts/`. Add `--push-wiki --cleanup-releases` to sync GitHub Wiki and clean old ignored local release artifacts after publishing.

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- Automatic updates use Sparkle and the public EdDSA key embedded in `mac-app/Info.plist`.
- PDF rendering uses PDFKit.
- EPUB and DOCX rendering uses WebKit. DOCX support is optimized for readable text extraction rather than exact Word layout fidelity.
- Search selections are kept separate from AI passage selection so search navigation does not accidentally populate the assistant.
- AI requests use the model, endpoint, language, and API key configured locally in the settings panel.

<p align="center">
  <img src="assets/leaf-reader-icon.png" alt="Leaf Reader icon" width="128">
</p>

# Leaf Reader

Leaf Reader is a native macOS reader for PDF, EPUB, and DOCX documents. It is built with Swift, PDFKit, and WebKit, and focuses on a quiet reading experience with fast navigation, document search, reading progress restore, light and dark reader themes, and an optional AI panel for working with selected passages.

## Language

- [English](#english)
- [中文 README](#中文)
- The website automatically follows the browser language and also provides a manual Chinese/English switch in the header: <https://leafreader.space/>

## 中文

Leaf Reader 是一个原生 macOS 文档阅读器，支持 PDF、EPUB 和 DOCX。它面向长文档阅读、学习和批注场景，提供阅读进度恢复、文档搜索、浅色/护眼/深色主题、AI 问答、选中文本翻译/解释/总结、背单词和本地朗读。

下载最新 macOS 安装包：

[下载 Leaf Reader 1.6.1 pkg 安装包](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

系统要求：

- macOS 12.0 Monterey 或更高版本。
- 支持 Apple Silicon 和 Intel Mac。
- AI 功能需要用户自行配置模型服务和 API Key；普通阅读不需要。
- KittenTTS 本地朗读支持 macOS 12.0 Monterey 或更高版本。
- Kokoro 本地朗读需要 macOS 14.0 或更高版本。

主要功能：

- 打开本地 PDF、EPUB、DOCX 文档，并自动恢复阅读位置。
- 支持文档搜索、PDF 翻页、书架、最近阅读、浅色/护眼/深色主题。
- 选中文本后可让 AI 解释、总结、翻译或继续追问上下文。
- 支持保存单词、复习新词、导出词表。
- 支持 KittenTTS 和 Kokoro 本地朗读；短词和短句可回退到 macOS 系统语音。
- 文档保存在本机；只有使用 AI 功能时，相关文本才会发送到用户配置的模型服务。

项目官网：<https://leafreader.space/>

许可证：Leaf Reader 使用 [Apache License 2.0](LICENSE) 许可发布。

## 更新记录

### 1.6.1

- 缩减安装包内置语音资源，只保留 KittenTTS 所需的 espeak 英文字典。
- 删除重复 Kokoro 英文声音，保留 Bella、Heart、Adam、Emma、George。
- 保持 KittenTTS 和 Kokoro 本地朗读在更小的 runtime 资源下正常工作。

### 1.6.0

- 使用统一主题色重新打磨阅读器、AI 聊天、设置、最近文档和词汇界面。
- 给选中文本浮动工具栏动作增加 SF Symbol 图标，并让工具栏布局更紧凑。
- 改进 AI 聊天气泡持久化、关联单词处理和跨阅读会话的来源标注。
- 增强 embedding 在回填、重建和切换文档时的生命周期与状态处理。
- 优化词汇复习/列表导航和最近文档清理流程。

### 1.5.11

- 将本地朗读播放和 runtime 安装代码拆分成更小的模块。
- 将 Kitten 专属的播放/进度代码重命名为适用于 Kokoro 和 KittenTTS 的通用朗读命名。
- 跨应用版本复用稳定的语音模型发布资源，模型归档未变化时无需重复上传。
- 后续可下载语音包只包含模型数据，runtime 二进制复用应用内置版本。
- 改进英文断句和 PDF、Web 文档中的朗读来源匹配。

### 1.5.10

- 将选中的 Kokoro 声音 `.bin` 文件打包进应用，语音可从本地恢复，不再从云端下载。
- 精简 Kokoro 云端 runtime 归档，移除重复声音文件和源码 `.mlpackage` 目录。
- 保持 Kokoro 英文和中文声音安装路径与所选书籍语言一致。

### 1.5.9

- 将朗读进度与已保存的 AI 来源锚点关联，朗读推进时展开的 AI 面板会滚动到相关分析。
- 同步 PDF、EPUB、DOCX 和 Web 阅读视图中的朗读进度、AI 翻译和关联单词气泡。
- 结合来源 key、单词 ID、页面范围和阅读进度，改进重复或部分文本的来源匹配。
- 将朗读 AI 跟踪逻辑拆成独立模块，便于后续维护 TTS 和 AI 面板行为。

### 1.5.8

- 使用 macOS 12.0 部署目标重新构建内置 KittenTTS `espeak-ng` helper runtime，使 KittenTTS 本地朗读匹配应用的 macOS 12 基线。
- 增加重建 macOS 12 兼容 `espeak-ng` 和 `pcaudiolib` runtime 依赖的脚本。
- 在旧 macOS 版本上保留 Kokoro 下载入口，并在系统低于 Kokoro 所需 macOS 14.0 时显示兼容性提示。
- 更新 README 和发布网站，说明应用、KittenTTS、Kokoro 的系统要求。

### 1.5.7

- Kokoro 播放改用 FluidAudio 的 `kokoro-ane` 英文变体，并使用用户选择的语速。
- 让 Kokoro 的设置行为与 KittenTTS 一致：缺少必要模型缓存时，朗读设置页显示未安装并提供下载按钮。
- 将 Kokoro 的 ANE 和 G2P 模型缓存与 runtime 下载打包在一起，安装后即可完整启用本地模型。

### 1.5.6

- 语音模型下载会边下载边写入部分文件，中断后的 GitHub 下载可以续传。
- 为 Kokoro 和 KittenTTS 下载增加自动重试和 HTTP 状态校验。
- 增加归档校验，避免服务器错误页面被当作 `tar` 包处理。
- 更新语音 runtime 下载文档，使其匹配应用实际使用的 GitHub Release URL。

### 1.5.5

- 修复语音模型删除逻辑，删除 Kokoro 时同时清理当前和旧模型缓存，并报告删除错误。
- 防止已删除或缺失的语音模型被 TTS 预热或回退逻辑重新启动。
- 当 Kokoro 和 KittenTTS 都被删除时，朗读设置界面保持稳定，包括禁用模型选择和正常关闭。
- 将 KittenTTS 放在语音模型选择和下载列表首位，匹配更小的默认模型路径。
- 简化语音 runtime 选择和清理代码，让下载取消、模型删除和朗读后端选择共用同一套 runtime 状态。

### 1.5.4

- 将生成的 TTS WAV 播放从 `NSSound` 切换到 `AVAudioPlayer`，提升蓝牙/耳机输出的可靠性。
- 增加播放 watchdog，避免 macOS 没有报告音频完成时朗读卡住。
- 每个 KittenTTS server 使用进程级随机本地端口，避免连接到旧应用实例残留的 server。
- 应用退出时同步停止朗读并终止 Kokoro/KittenTTS 子进程。

### 1.5.3

- 内置 KittenTTS 所需的 `espeak-ng` runtime、动态库和数据文件，KittenTTS 不再依赖 Homebrew 安装。
- KittenTTS 优先使用应用内签名的 server，同时继续使用下载的模型文件。
- 增加构建回退：本地 runtime 目录缺失时，从语音 runtime 归档中提取内置 KittenTTS server。
- 新下载的 runtime 如果是唯一可用模型，或之前选择的模型不可用，会自动切换朗读设置。

### 1.5.2

- 修复 Kokoro 语音状态，新安装缺少完整模型文件时不再误显示为已安装。
- Kokoro 播放优先使用应用内签名 runtime，并从用户缓存读取下载模型文件。
- KittenTTS 继续使用更小的内置 server runtime 路径，模型单独下载。

### 1.5.1

- 将小型 KittenTTS server 和 Kokoro CLI runtime 打包进应用，用户只需下载语音模型。
- 大型 KittenTTS 和 Kokoro 模型保持在安装包外，以缩小安装包体积。
- KittenTTS 使用内置 server 搭配下载的用户模型，并移除未使用的 CLI 回退路径。
- 合成失败后自动重启 KittenTTS server，以恢复卡住的本地 server 进程。
- 新朗读设置默认选择 KittenTTS，优先使用最小下载模型路径。

### 1.5.0

- 改进 PDF 连续朗读，自动翻页后从下一页顶部继续，而不是从页面中间开始。
- 切换或移除书籍时立即停止当前朗读，避免继续播放上一份文档的 TTS。
- 缓存朗读进度更新时的当前页文本，降低 PDF TTS 高亮开销。
- 阅读 PDF 时避免隐藏 WebKit 选择和高亮清理工作，减少 WebContent 图层噪音。
- 整理 PDF 朗读状态处理，让暂停、恢复、停止和页面变化恢复共用更安全的逻辑。

### 1.4.18

- 在浮动文本选择工具栏末尾增加复制按钮，便于快速复制 PDF 和 Web 文本。
- 修复 PDF 右键行为，让选中文本保持选中，同时保留 PDFKit 原生上下文菜单动作。
- 增加中文语音自动选择，安装中文系统声音后可朗读选中的中文文本。
- 改进最近文档、AI 对话、EPUB 缓存清理、EPUB HTML 写入和单词记录存储失败的诊断信息。
- 将阅读器工具栏和布局代码拆分到更聚焦的文件中。

### 1.4.17

- 改进 EPUB 加载诊断，缺失、无效或无法解码的章节会给出错误信息，不再静默跳过。
- 当没有可读 spine 内容时，EPUB 回退页会显示有用诊断。
- Web 阅读位置恢复和 AI 来源跳转改为事件驱动，提高大型 EPUB 和 DOCX 文档中的可靠性。
- 改进阅读会话进度处理，包括更清晰地处理缺失 Web 进度和更安全地保存 PDF 页面。
- 加固 AI 设置持久化，并为模型、embedding 和对话选项增加隔离默认值测试。
- 按领域拆分逻辑测试，便于后续回归覆盖。

### 1.4.12

- 使用快速文档标识替代整文件 MD5 读取，提升首次加载性能，并兼容已有保存数据。
- 增加加载遮罩，打开文档前等待初始 AI 气泡布局完成。
- AI 面板启动时优先恢复最近气泡，并按需加载匹配的历史气泡，减少启动工作量。
- 收紧提示词、Markdown 间距和原文/译文之间的空行处理，使 AI 解释更紧凑。
- 改进 PDF 滚动翻页，返回上一页时落到上一页底部，减少“跳页”观感。
- 对昂贵的面板和 PDF 布局刷新做 debounce，降低窗口 resize 卡顿。

### 1.4.11

- 修复手动检查更新流程，发现更新后更新窗口不再立刻消失。
- 等待 Sparkle 当前检查会话完全结束后，再展示标准更新界面。

### 1.4.10

- 改进 EPUB 目录解析，支持嵌套 NCX、HTML nav 深度、相对路径、片段和 query 清理。
- 改进 EPUB 内容兼容性，包括声明编码、HTML 实体解码、内部链接导航和图片懒加载。
- 加固 EPUB 归档/资源路径处理，并清理不安全的内嵌 HTML 内容。
- 将 EPUB 加载逻辑拆分为 parser、path resolver、sanitizer 和 text decoder helper，并增加共享逻辑测试。

### 1.4.9

- 轮换 Sparkle 更新签名密钥，并内置新的更新公钥。
- 更新发布签名流程，使用项目外部备份的 Sparkle 私钥。
- 这是一个手动安装过渡版本；从该版本开始，后续更新可再次使用应用内自动更新。

### 1.4.8

- 修复 EPUB 单词标记为 Learn English 时产生重复 AI 记录的问题。
- 修复历史 AI 对话中旧单词气泡被重复恢复的问题。
- 修复发布安装包，使 macOS Installer 将 Leaf Reader 升级到 `/Applications`，而不是迁移到旧应用路径。

### 1.4.7

- 使用缓存解包、延迟纯文本提取和更快的封面读取优化 EPUB 加载。
- 修复 EPUB 封面/首页渲染，有封面时第一页会打开实际封面。
- 改进 EPUB 单词高亮，Learn English 会立即标记选中单词，并更准确地恢复高亮。
- 增加可点击的 EPUB AI 来源下划线，可跳回匹配的 AI 对话。
- 为书架增加清理控制，可清理单本书的 AI 数据、单词记录、向量缓存和阅读历史。

### 1.4.6

- 修复手动检查更新，在 Sparkle 报告无更新后显示白色“已是最新版本”结果窗口。
- 为成功完成但没有详细无更新回调的检查流程增加回退路径。

### 1.4.5

- 设置二进制部署目标为 macOS 12.0，修复 macOS 13.6.1 无法打开 Leaf Reader 的发布构建问题。
- 将应用构建为同时支持 Apple Silicon 和 Intel Mac 的 universal macOS 二进制。
- 为手动检查更新增加白色进度窗口。
- 降低 AI 气泡面板在流式输出和文本选择时的重新布局工作量。
- 将书架封面磁盘缓存加载移出主线程。

### 1.4.4

- 用 Leaf Reader 白底状态窗口替换手动“已是最新版本”更新检查对话框。
- 保留 Sparkle 对可用更新的发现和安装流程。
- 防止 AppleDouble 元数据文件被复制进生成的应用和安装包 payload。

### 1.4.2

- 增加基于 Sparkle 的应用内更新检查。
- 发布 GitHub Pages 下载网站和 appcast feed。
- 增加自动构建和发布打包脚本。
- 改进 EPUB/DOCX 在切换到 AI 气泡选择时的选择清理。

### 1.4.1

- 改进阅读区域和 AI 聊天气泡之间的选择处理，确保只保留一个活跃选择。
- 使用追问时保留 AI 气泡选择，并将选中的气泡文本作为追问上下文恢复。
- 保留选中文本供 Learn English、总结和翻译动作使用。

### 1.4

- 重做书籍词汇面板，增加学习、复习、新词和全部标签页，支持分页词表、导出和小写复习卡片。
- 将单词记录迁移到 SQLite，支持增量 upsert/delete 持久化，并增加生产 SQLite 回归测试。
- 改进拖放导入，包括单本/多本拖放、重复处理、书架聚焦和最近阅读排序。
- 增加 AI 对话裁剪、debounce 保存和关联单词气泡保留。
- 修复 embedding provider 默认值、SiliconFlow 设置、provider 专属 API key，以及使用缓存 embedding norm 加速向量评分。
- 将大型 AI、设置、词汇和存储文件拆分为更聚焦的模块，并扩大回归测试覆盖。

### 1.3.1

- 增加在阅读器窗口直接拖放打开 PDF、EPUB 和 DOCX 文件。
- 增加按书保存 AI 对话的选项，包括非词汇 AI 气泡的来源页码/位置。
- 点击已保存的非词汇 AI 气泡可跳回记录的页面或阅读位置。
- 改进切换书籍时的向量索引状态重置，避免新文档显示旧缓存状态。
- 将阅读器窗口控制器拆分为 AI、文档加载、embedding、导航、会话、UI 和词汇等聚焦扩展。

### 1.3

- 增加书架视图，支持更高分辨率封面、阅读进度、添加文件和上下文操作。
- 改进词汇流程，包括单词聚合、Anki CSV 导出、来源页/上下文、发音播放和更安全的失败查询处理。
- 在底部工具栏增加更清晰的 embedding 状态，包括已缓存、空闲、暂停和重试。
- 改进后台索引，让大书打开更快，并让向量生成等待阅读器空闲。
- 重做设置、书架和词汇面板的模态焦点处理。
- 增加更安全的缓存和单词记录清理确认提示。

### 1.2

- 将助手入口重命名为本地化的 Learn English 标签，并改进选中单词和短语解释。
- 为 AI 回答、引用气泡和书籍词汇面板增加 Markdown 渲染。
- 增加 PDF 向量检索用于文档问答，支持当前页优先、后台索引、缓存复用和底部工具栏索引进度。
- 增加独立 embedding 服务设置，包括 OpenAI 兼容 provider、本地 embedding 端点、自定义端点和独立 embedding API key。
- 改进针对英文书籍的中文提问到英文检索查询。
- 重设计设置面板，支持滚动布局、更清晰的字段和更明显的窗口边缘。
- 将书籍词汇面板重做为可滚动卡片视图。
- 用子窗口替代脆弱的 sheet 面板，提升应用稳定性。

## English

## License

Leaf Reader is licensed under the [Apache License 2.0](LICENSE).

## Screenshots

![Leaf Reader word learning in light mode](assets/reader-light-ai-word.png)

![Leaf Reader bookshelf](assets/reader-bookshelf.png)

![Leaf Reader settings](assets/reader-settings.png)

![Leaf Reader passage explanation in dark mode](assets/reader-dark-ai.png)

![Leaf Reader vocabulary review](assets/reader-dark-vocabulary.png)

## Download

Download the latest macOS installer:

[Leaf Reader 1.6.1 pkg installer](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

Project website:

https://leafreader.space/

## System Requirements

- macOS 12.0 Monterey or later.
- Apple Silicon or Intel Mac.
- An API key is optional and only needed for AI features.
- Optional Kokoro local speech requires macOS 14.0 or later. KittenTTS local speech supports the app baseline, macOS 12.0 Monterey or later.

## Highlights

- Open local PDF, EPUB, and DOCX files in one macOS app.
- Restore the last opened document, page, zoom level, and reading position.
- Navigate PDFs with toolbar controls, keyboard paging, scroll paging, and direct page-number entry.
- Search documents with `Command+F`, next and previous result controls, and visible result positioning.
- Switch between light and dark reader themes for the document area, search overlay, recent files panel, and AI chat panel.
- Select text and ask the built-in AI assistant to explain, summarize, or translate passages.
- Read selected English or Chinese text with optional downloadable Kokoro or KittenTTS output where supported; otherwise Leaf Reader falls back to macOS system voices.
- Configure model, API key, interface language, and reader theme from the in-app settings panel.
- Keep documents local; AI requests are only sent when the assistant is used with the configured API key.

## Optional Speech Runtimes

Leaf Reader can use [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) or [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs) for local text-to-speech. Kokoro provides English and Chinese voices; KittenTTS is used for English read aloud. Small speech runtime executables are bundled in the installer; large model files are downloaded on demand. Open Settings -> AI Analysis -> Speech to download Kokoro or KittenTTS.

Runtime priority is automatic: KittenTTS first, then Kokoro. Short word or phrase selections use Apple TTS directly.

Runtime OS requirements:

- Kokoro local speech requires macOS 14.0 or later.
- KittenTTS local speech supports macOS 12.0 Monterey or later.
- The main reader app still supports macOS 12.0 Monterey or later. On older systems, Kokoro downloads show a compatibility warning before continuing.

Speech model downloads currently point to the stable `v1.5.10` speech asset release:

- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kokoro-coreml-macos-arm64.tar.gz` (Kokoro ANE/G2P model cache)
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kitten-tts-rs-macos-arm64.tar.gz` (KittenTTS mini model)

Regular app releases reuse those files. The native runtime binaries are bundled with the app; regenerated speech archives should only be published when model files change, then `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag` should be updated to the new asset tag.

Generate speech model packages with:

```sh
./scripts/package_speech_models.sh
```

The packaging script also writes `docs/tts/speech-models-manifest.json` with each asset's file size and SHA256 digest. When model files change, update `runtimeAssetsReleaseTag` to the release tag that will host the new model assets and publish with `--with-speech-models`.

## What's New in 1.6.1

- Reduced the bundled speech footprint by keeping only the espeak English dictionary needed by KittenTTS.
- Trimmed duplicate Kokoro English voices while keeping Bella, Heart, Adam, Emma, and George available.
- Kept KittenTTS and Kokoro local playback working with the smaller bundled runtime resources.

## What's New in 1.6.0

- Refined the reader, AI chat, settings, recent documents, and vocabulary surfaces with a shared theme palette.
- Added SF Symbol icons to the selected-text floating toolbar actions and tightened the toolbar layout.
- Improved AI chat bubble persistence, linked word handling, and source annotations across reading sessions.
- Made embedding lifecycle/status handling more resilient during backfill, rebuild, and document changes.
- Polished vocabulary review/list navigation and recent document cleanup flows.

## What's New in 1.5.11

- Reorganized local speech playback and runtime installation code into smaller focused modules.
- Renamed Kitten-specific playback/progress code to generic read-aloud naming for Kokoro and KittenTTS.
- Reused stable speech model release assets across app releases, so unchanged model archives do not need to be uploaded again.
- Changed future downloadable speech packages to contain model data only while reusing the runtime binaries bundled with the app.
- Improved English sentence splitting and read-aloud source matching for PDF and web-backed documents.

## What's New in 1.5.10

- Bundled the selected Kokoro voice `.bin` files with the app so speech voices are restored locally instead of being downloaded from the cloud.
- Trimmed Kokoro cloud runtime archives so they contain model/runtime files without duplicate voice binaries or source `.mlpackage` directories.
- Kept Kokoro English and Chinese voice installation paths consistent with the selected book language.

## What's New in 1.5.9

- Linked read-aloud progress with saved AI source anchors, so the expanded AI panel scrolls to related analysis while the spoken passage advances.
- Synced read-aloud progress with AI translation and linked word bubbles for PDF, EPUB, DOCX, and web-backed reading views.
- Improved source matching for repeated or partial passages by combining source keys, word IDs, page bounds, and reading progress.
- Split the read-aloud AI tracking logic into a focused module to make future TTS and AI panel behavior easier to maintain.

## What's New in 1.5.8

- Rebuilt the bundled KittenTTS `espeak-ng` helper runtime with a macOS 12.0 deployment target, so KittenTTS local speech matches the app's macOS 12 baseline.
- Added a reusable script for rebuilding the macOS 12-compatible `espeak-ng` and `pcaudiolib` runtime dependencies before release packaging.
- Kept Kokoro downloads available on older macOS versions while showing a compatibility warning when the system is below Kokoro's macOS 14.0 runtime requirement.
- Updated README and the release website to clarify the app, KittenTTS, and Kokoro operating system requirements.

## What's New in 1.5.7

- Updated Kokoro playback to use FluidAudio's `kokoro-ane` English variant with the selected speech speed.
- Made Kokoro match KittenTTS settings behavior: if the required model cache is missing, the Speech settings page shows it as not installed and offers a download button.
- Packaged Kokoro's ANE and G2P model caches together with the runtime download so installing Kokoro fully enables the local model.

## What's New in 1.5.6

- Made speech model downloads write partial files as data arrives, so interrupted GitHub downloads can resume instead of restarting from zero.
- Added automatic retry and HTTP status validation for Kokoro and KittenTTS downloads.
- Added archive validation so server error pages are reported as download failures instead of being passed to `tar`.
- Updated speech runtime download documentation to match the GitHub Release URLs used by the app.

## What's New in 1.5.5

- Fixed speech model deletion so removing Kokoro clears both current and legacy model caches and reports deletion errors instead of silently keeping stale files.
- Prevented deleted or missing speech models from being restarted by TTS warmup or fallback logic.
- Made the speech settings UI stable when both Kokoro and KittenTTS are removed, including disabled model selection and close behavior.
- Put KittenTTS first in speech model selection and download rows, matching the smaller default model path.
- Simplified speech runtime selection and cleanup code so download cancellation, model deletion, and read-aloud backend choice use one shared runtime state.

## What's New in 1.5.4

- Switched generated TTS WAV playback from `NSSound` to `AVAudioPlayer` to improve reliability on Bluetooth/headphone output routes.
- Added playback watchdogs so read-aloud advances instead of hanging when macOS never reports audio completion.
- Started each KittenTTS server on a per-process random local port to avoid connecting to stale server processes from an older app instance.
- Made app termination synchronously stop speech playback and terminate Kokoro/KittenTTS child processes.

## What's New in 1.5.3

- Bundled KittenTTS' required `espeak-ng` runtime, dylibs, and data files so KittenTTS no longer depends on a Homebrew install.
- Made KittenTTS prefer the signed server bundled inside the app while continuing to use downloaded model files.
- Added a build fallback that extracts the bundled KittenTTS server from the speech runtime archive when the local runtime directory is missing.
- Automatically switches speech settings to a newly downloaded runtime when it is the only usable model, or when the previous selection is no longer installed.

## What's New in 1.5.2

- Fixed Kokoro speech status so new installs no longer show Kokoro as installed unless the downloaded model files are complete.
- Made Kokoro playback prefer the signed runtime bundled inside the app while using downloaded model files from the user cache.
- Kept KittenTTS on the smaller bundled server runtime path with models downloaded separately.

## What's New in 1.5.1

- Bundled the small KittenTTS server and Kokoro CLI runtimes inside the app so users only need to download speech models.
- Kept large KittenTTS and Kokoro models outside the installer to reduce package size.
- Made KittenTTS use the bundled server with downloaded user models, and removed the unused CLI fallback path.
- Restarted the KittenTTS server automatically after failed synthesis to recover from stale local server processes.
- Defaulted new speech settings to KittenTTS so the smallest downloadable model path is selected first.

## What's New in 1.5.0

- Improved PDF read-aloud continuation so automatic page turns resume from the top of the next page instead of starting mid-page.
- Stopped active read-aloud immediately when switching or removing books, preventing stale TTS playback from the previous document.
- Reduced PDF TTS highlight overhead by caching active page text during read-aloud progress updates.
- Avoided hidden WebKit selection and highlight cleanup work while reading PDFs, reducing WebContent layer volatility noise.
- Cleaned up PDF read-aloud state handling so pause, resume, stop, and page-change recovery share safer tracking logic.

## What's New in 1.4.18

- Added a Copy button at the end of the floating text-selection toolbar for faster PDF and web text copying.
- Fixed PDF right-click behavior so selected text stays selected and PDFKit's native context-menu actions remain available.
- Added automatic Chinese speech voice selection so selected Chinese text can be read aloud when a Chinese system voice is installed.
- Improved diagnostics for recent documents, AI conversations, EPUB cache cleanup, rendered EPUB HTML writes, and word-record storage failures.
- Split reader toolbar and layout code into focused files to make future UI work easier to maintain.

## What's New in 1.4.17

- Improved EPUB loading diagnostics so missing, invalid, or undecodable chapters are reported instead of being silently skipped.
- Made EPUB fallback pages show useful diagnostics when no readable spine content can be loaded.
- Made web reading-position restores and AI source jumps event-driven, improving reliability on large EPUB and DOCX documents.
- Improved reader session progress handling, including clearer handling for missing web progress and safer PDF page saves.
- Hardened AI settings persistence with isolated defaults coverage for model, embedding, and conversation options.
- Split logic tests by domain to make future regression coverage easier to maintain.

## What's New in 1.4.12

- Improved first-load performance by replacing full-file MD5 reads with a fast document identifier while preserving compatible access to existing saved data.
- Added a loading overlay that waits for the initial AI bubble layout before opening the document.
- Reduced AI panel startup work by restoring only recent bubbles first and loading matching historical bubbles on demand.
- Made AI explanations more compact by tightening prompts, Markdown spacing, and blank-line handling between original text and translation.
- Improved PDF scroll paging so moving to the previous page lands at the previous page bottom, reducing apparent skipped-page behavior.
- Reduced resize stutter by debouncing expensive panel and PDF layout refresh work.

## What's New in 1.4.11

- Fixed the manual Check for Updates flow so the update window does not disappear immediately after an update is found.
- Waits for Sparkle's current update check session to fully finish before presenting the standard update UI.

## What's New in 1.4.10

- Improved EPUB table-of-contents parsing for nested NCX entries, HTML nav depth, relative paths, fragments, and query stripping.
- Improved EPUB content compatibility with declared text encodings, HTML entity decoding, internal link navigation, and lazy image loading.
- Hardened EPUB archive/resource path handling and sanitized unsafe embedded HTML content.
- Split EPUB loading logic into focused parser, path resolver, sanitizer, and text decoder helpers with shared logic tests.

## What's New in 1.4.9

- Rotated the Sparkle update signing key and embedded the new update public key.
- Updated release signing to use the project-external Sparkle private key backup.
- This is a manual-install transition release; future updates from this version can use in-app automatic updates again.

## What's New in 1.4.8

- Fixed duplicate AI records when marking EPUB words for Learn English.
- Fixed old word bubbles being restored twice in historical AI conversations.
- Fixed release installers so macOS Installer upgrades Leaf Reader in `/Applications` instead of relocating it to an old app path.

## What's New in 1.4.7

- Optimized EPUB loading with cached unpacking, deferred plain-text extraction, and faster cover reads.
- Fixed EPUB cover/home rendering so the first page opens on the actual cover when available.
- Improved EPUB word highlighting so Learn English marks the selected word immediately and restores highlights more accurately.
- Added clickable EPUB AI source underlines that jump back to the matching AI conversation.
- Added shelf cleanup controls for clearing per-book AI data, word records, vector cache, and reading history.

## What's New in 1.4.6

- Fixed manual update checks so the white "You're up to date" result window is shown after Sparkle reports no update.
- Added a fallback path for update probe cycles that finish successfully without a detailed no-update callback.

## What's New in 1.4.5

- Fixed the release build so macOS 13.6.1 can open Leaf Reader by setting the binary deployment target to macOS 12.0.
- Built the app as a universal macOS binary for both Apple Silicon and Intel Macs.
- Added a white progress window for manual update checks.
- Reduced AI bubble panel relayout work during streaming and text selection.
- Moved shelf cover disk-cache loading off the main thread.

## What's New in 1.4.4

- Replaced the manual "up to date" update check dialog with a Leaf Reader white-background status window.
- Kept Sparkle's update discovery and installation flow for available updates.
- Prevented AppleDouble metadata files from being copied into generated app and installer payloads.

## What's New in 1.4.2

- Added Sparkle-powered in-app update checks.
- Published the GitHub Pages download site and appcast feed.
- Added automated build and release packaging scripts.
- Improved EPUB/DOCX selection clearing when switching to AI bubble selections.

## What's New in 1.4.1

- Refined selection handling between the reading area and AI chat bubbles so only one active selection is kept.
- Preserved AI bubble selections when using follow-up questions, and restored selected bubble text as follow-up context.
- Kept selected passages available for Learn English, Summarize, and Translate actions.

## What's New in 1.4

- Reworked the book vocabulary panel with separate Learn, Review, New Words, and All tabs, paginated word lists, exports, and lower-case review cards.
- Moved word records to SQLite with incremental upsert/delete persistence and production SQLite regression tests.
- Improved drag-and-drop import behavior for one-book and multi-book drops, duplicate handling, bookshelf focus, and recent-reading sorting.
- Added AI conversation trimming, debounced saves, and preserved linked word bubbles.
- Fixed embedding provider defaults, SiliconFlow settings, provider-specific API keys, and faster vector scoring with cached embedding norms.
- Split large AI, settings, vocabulary, and storage files into focused modules with broader regression coverage.

## What's New in 1.3.1

- Added drag-and-drop opening for PDF, EPUB, and DOCX files directly in the reader window.
- Added optional AI conversation saving per book, including source page/location for non-vocabulary AI bubbles.
- Clicking saved non-vocabulary AI bubbles can jump back to the recorded page or reading position.
- Improved vector-index state reset when switching books so old cache status is not shown for the new document.
- Split the reader window controller into focused extensions for AI, document loading, embedding, navigation, sessions, UI, and vocabulary logic.

## What's New in 1.3

- Added a bookshelf view with higher-resolution covers, reading progress, add-file support, and contextual actions.
- Improved vocabulary workflows with word aggregation, Anki CSV export, source page/context, pronunciation playback, and safer failed-query handling.
- Added clearer embedding status in the bottom toolbar, including cached, idle, paused, and retry states.
- Improved background indexing so large books open faster and vector generation waits for reader idle time.
- Reworked modal focus handling for settings, bookshelf, and vocabulary panels.
- Added safer cache and word-record clearing with confirmation prompts.

## What's New in 1.2

- Renamed the assistant entry point to the localized Learn English label and improved selected-word and short-phrase explanations.
- Added Markdown rendering for AI answers, reference bubbles, and the book vocabulary panel.
- Added PDF vector retrieval for document Q&A, with current-page priority, background indexing, cache reuse, and index progress in the bottom toolbar.
- Added separate embedding service settings, including OpenAI-compatible providers, local embedding endpoints, custom endpoints, and a separate embedding API key.
- Improved Chinese-to-English retrieval queries when asking Chinese questions about English books.
- Redesigned the settings panel with scrolling layout, clearer fields, and a more visible window edge.
- Reworked the book vocabulary panel into a scrollable card view.
- Improved app stability by replacing fragile sheet-based panels with child windows.

## Requirements

- macOS 12.0 Monterey or later.
- Swift toolchain with Cocoa, PDFKit, WebKit, and CryptoKit frameworks.
- An API key for AI features, configured inside the app settings.

## Run

Open a locally built app bundle:

```sh
open "Leaf Reader.app"
```

The app bundle is generated locally and is not committed to git.

## Build From Source

Install Sparkle first:

```sh
brew install --cask sparkle
```

Build the macOS 12-compatible KittenTTS `espeak-ng` helper runtime:

```sh
brew install autoconf automake libtool pkgconf
./scripts/build_espeak_ng_runtime.sh
```

Create the app bundle directory if needed, then compile the Swift sources:

```sh
./scripts/build_app.sh
```

Then run it:

```sh
open "Leaf Reader.app"
```

## Tests

Run the lightweight logic regression tests:

```sh
./tests/run.sh
```

Run the full local pre-commit check, including whitespace checks, tests, and an app build:

```sh
./scripts/check.sh
```

## Project Layout

- `Leaf Reader.app` - generated macOS application bundle, ignored by git.
- `mac-app/*.swift` - native Swift source code.
- `tests/` - lightweight Swift logic regression tests.
- `mac-app/AIPrompts.json` - built-in AI prompt definitions.
- `mac-app/AppIcon.icns` - packaged app icon.
- `mac-app/AppIconSource.png` - source image for the app icon.
- `docs/` - GitHub Pages site and Sparkle update feed.
- `assets/leaf-reader-icon.png` - project icon used in this README.
- `assets/reader-light-ai-word.png` - light mode word-learning screenshot.
- `assets/reader-bookshelf.png` - bookshelf screenshot.
- `assets/reader-settings.png` - settings panel screenshot.
- `assets/reader-dark-ai.png` - dark mode AI reading screenshot.
- `assets/reader-dark-vocabulary.png` - vocabulary review screenshot.
- `release/` - local release artifacts when generated.

## Code Wiki

Developer notes live in `docs/wiki/`:

- [Code Wiki index](docs/wiki/index.md)
- [Code Map](docs/wiki/code-map.md)

Regenerate the code map after larger refactors:

```sh
./scripts/generate_code_wiki.sh
```

Preview and sync the GitHub Wiki copy:

```sh
./scripts/sync_github_wiki.sh
./scripts/sync_github_wiki.sh --push
```

## Release

Current version: `1.6.1`

Git tag: `v1.6.1`

Latest installer:

[Leaf Reader-1.6.1.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

Local release artifacts are expected under:

```text
release/1.6.1/
```

Sparkle updates use:

```text
https://leafreader.space/appcast.xml
```

The appcast entry points to the signed and notarized pkg uploaded to GitHub Releases. `scripts/release_pkg.sh` regenerates `docs/appcast.xml` with the new version, pkg URL, file length, and EdDSA signature from Sparkle's `sign_update` tool.

Build, sign, notarize, staple, and update the Sparkle appcast for a release:

```sh
SPARKLE_PRIVATE_KEY_FILE=/path/to/sparkle-ed25519-private-key ./scripts/release_pkg.sh 1.6.1
```

Run the full publish flow from a clean working tree:

```sh
./scripts/publish_release.sh 1.6.1
```

The publish script runs tests, builds/signs/notarizes the pkg, commits the version/appcast changes, tags the release, pushes `main` and the tag, creates the GitHub Release, uploads the pkg, and verifies the download URL. Pass `--with-speech-models` only when publishing changed speech model archives in `docs/tts/`.

The release script accepts the Sparkle private key through the configured release-machine environment. Keep the private key out of git and store recovery details only in private operational notes. Losing the private key breaks automatic updates for apps that already ship with the matching public key.

## Notes

- Bundle identifier: `com.linlu.leafreader`.
- Automatic updates use Sparkle and the public EdDSA key embedded in `mac-app/Info.plist`.
- PDF rendering uses PDFKit.
- EPUB and DOCX rendering uses WebKit. DOCX support is optimized for readable text extraction rather than exact Word layout fidelity.
- Search selections are kept separate from AI passage selection so search navigation does not accidentally populate the assistant.
- AI requests use the model, endpoint, language, and API key configured locally in the settings panel.

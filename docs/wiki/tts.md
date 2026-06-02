# TTS 与朗读

关键词：TTS、朗读、语音、KittenTTS、Kokoro、运行时、快捷键、下划线、高亮。

这页用于维护本地语音播放、朗读进度高亮和可下载 TTS 模型运行时。

## 使用入口

- 顶部工具栏：开始朗读、停止、重播当前朗读条目。
- 底部朗读浮动工具条：上一条、播放/暂停、停止、下一条、重播、语速。
- 快捷键：`[` 往前朗读一条，`]` 重复当前朗读条目。
- AI 气泡和单词气泡里的发音按钮：短文本发音，优先使用可用本地 TTS，必要时回退到系统语音。

朗读浮动工具条会提示快捷键，帮助用户理解 `[`、`]` 等按键的含义。

## 运行时结构

```text
ReaderWindowController+ReadAloud
  -> SpeechPlaybackCoordinator
     -> SpeechRuntimeResourceManager
        -> KittenTTS runtime
        -> Kokoro Core ML runtime
     -> AVAudioPlayer
  -> ReaderWindowController+ReadAloudProgress
```

短单词、AI 面板短句和不适合走本地模型的内容，可以通过 `SpeechUtteranceFactory` 回退到 `NSSpeechSynthesizer`。

## 播放流程

```text
阅读文本
  -> SpeechTextPolicy 分段和清洗
  -> SpeechPlaybackCoordinator 选择运行时
  -> 生成或复用 WAV
  -> AVAudioPlayer 播放
  -> ReadAloudProgress 更新下划线和高亮
```

如果用户通过浮动窗口或快捷键切换上一条/下一条，而当前页不在朗读位置，阅读器会跳转到对应页面和位置。

## 主要文件

- `SpeechPlaybackCoordinator.swift`：语音播放中枢，负责选择运行时、文本分段、WAV 文件、播放控制和进度通知。
- `KokoroWorkerResponseReader.swift`：解析 Kokoro worker 的 JSON-line 响应，并忽略不相关 request id。
- `SpeechTextPolicy.swift`：TTS 文本归一化、英文候选判断和朗读分段。
- `SpeechRuntimeResourceManager.swift`：运行时安装检测、下载 URL、模型大小、兼容性、暂停/恢复/取消和清理。
- `RuntimeDownload.swift`：URLSession 下载、进度、断点数据和 HTTP 错误处理。
- `AISettingsPanelController+Speech.swift`：设置页里选择、下载、暂停、取消、删除和兼容性警告。
- `AISettingsPanelController+Build.swift`：朗读设置行、模型选择器、状态标签、按钮和进度条。
- `ReaderWindowController+ReadAloud.swift`：PDF 和 WebKit 内容的文档级朗读入口。
- `ReaderWindowController+ReadAloudProgress.swift`：朗读时的当前段落下划线和高亮更新。
- `AIChatPanel+Actions.swift`：AI 文本发音，优先本地 TTS，必要时系统语音回退。
- `ReaderWindowController+VocabularyActions.swift`：单词发音、中断行为和回退语音。
- `SpeechUtteranceFactory.swift`：系统语音的通用 utterance 设置。

## 运行时规则

- macOS 12 及以上默认目标是 KittenTTS。
- Kokoro 可以在旧系统下载，但运行需要 macOS 14 或以上；不兼容系统会在设置页提示。
- `SpeechRuntimeResourceManager.isDownloaded(_:)` 只检查运行时文件是否存在。
- `SpeechRuntimeResourceManager.isRunnable(_:)` 同时检查文件和当前 macOS 版本要求。
- `SpeechRuntimeResourceManager.runnableRuntime(preferredID:)` 是播放代码选择运行时的统一入口。
- 运行时安装会写入 `.leafreader-install-manifest.json`；manifest 写入失败会中止安装并回滚。
- 删除运行时时，只删除 Leaf Reader 安装的 FluidAudio 缓存目录，并兼容旧安装。
- 下载状态包含 active task id，避免已取消或被替换的下载回调覆盖当前状态。
- 下载失败会按运行时保存，并显示在设置页，直到下一次下载成功、取消或删除。
- KittenTTS server 超时后会取消 URLSession task，避免旧响应修改已完成状态。
- Kokoro CLI 回退有超时；删除非当前运行时不应停止正在播放的运行时。

## 打包与发布

- `scripts/build_espeak_ng_runtime.sh`：构建 KittenTTS 需要的低部署版本 `espeak-ng` 和 `pcaudiolib`。
- `scripts/build_app.sh`：把语音运行时复制进 app bundle，并验证 bundle 布局。
- `scripts/package_speech_models.sh`：打包可下载 TTS 模型，生成 `docs/tts/speech-models-manifest.json` 的大小和 SHA256。
- `scripts/package_speech_runtimes.sh`：旧兼容 wrapper，当前主要使用模型打包脚本。
- `scripts/publish_release.sh`：上传发布产物；只有模型归档变化时才传 `--with-speech-models`。

模型下载 URL 指向 `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag`，不是普通 app 版本号。常规 app 发布不需要重复上传未变化的模型归档。

修改内置原生运行时二进制后，发布前要用 `vtool` 或 `otool` 检查最低 macOS 版本。

## 检查

```sh
./tests/run.sh
./scripts/build_app.sh
./scripts/check.sh --no-build
```

下载行为至少覆盖这些状态：

- 运行时不存在
- 正在下载
- 已暂停
- 已安装且兼容
- 已下载但当前 macOS 不兼容

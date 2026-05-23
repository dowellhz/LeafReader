<p align="center">
  <img src="assets/leaf-reader-icon.png" alt="Leaf Reader icon" width="128">
</p>

# Leaf Reader

Leaf Reader 是一个原生 macOS 文档阅读器，支持 PDF、EPUB 和 DOCX。它面向长文档阅读、学习和批注场景，提供阅读进度恢复、文档搜索、浅色/护眼/深色主题、AI 问答、选中文本翻译/解释/总结、背单词和本地朗读。

## 语言 / Language

- 中文：当前文件
- [English README](README.md)
- 官网会根据浏览器语言自动显示中文或英文，也可以在页面右上角手动切换：<https://leafreader.space/>

## 许可证

Leaf Reader 使用 [Apache License 2.0](LICENSE) 许可发布。

## 截图

![Leaf Reader 亮色模式单词学习](assets/reader-light-ai-word.png)

![Leaf Reader 书架](assets/reader-bookshelf.png)

![Leaf Reader 设置](assets/reader-settings.png)

![Leaf Reader 深色模式 AI 阅读](assets/reader-dark-ai.png)

![Leaf Reader 背单词复习](assets/reader-dark-vocabulary.png)

## 下载

下载最新 macOS 安装包：

[下载 Leaf Reader 1.6.1 pkg 安装包](https://github.com/dowellhz/LeafReader/releases/download/v1.6.1/LeafReader-1.6.1.pkg)

项目官网：

<https://leafreader.space/>

## 系统要求

- macOS 12.0 Monterey 或更高版本。
- 支持 Apple Silicon 和 Intel Mac。
- AI 功能需要用户自行配置模型服务和 API Key；普通阅读不需要。
- KittenTTS 本地朗读支持 macOS 12.0 Monterey 或更高版本。
- Kokoro 本地朗读需要 macOS 14.0 或更高版本。

## 主要功能

- 打开本地 PDF、EPUB、DOCX 文档。
- 自动恢复上次打开的文档、页码、缩放和阅读位置。
- 使用工具栏、键盘、滚动翻页和页码输入快速导航 PDF。
- 使用 `Command+F` 搜索文档，并在结果之间前后跳转。
- 在文档区域、搜索面板、书架和 AI 面板中切换浅色、护眼和深色主题。
- 选中文本后让 AI 解释、总结、翻译或继续追问上下文。
- 从阅读内容中保存单词，支持复习、新词、全部列表和导出。
- 支持 KittenTTS 和 Kokoro 本地朗读；短词和短句可回退到 macOS 系统语音。
- 在设置中配置模型、API Key、界面语言、阅读主题和朗读模型。
- 文档保存在本机；只有使用 AI 功能时，相关文本才会发送到用户配置的模型服务。

## 可选朗读模型

Leaf Reader 可以使用 [FluidAudio Kokoro Core ML](https://huggingface.co/FluidInference/kokoro-82m-coreml) 或 [kitten_tts_rs](https://github.com/second-state/kitten_tts_rs) 进行本地朗读。Kokoro 提供英文和中文声音，KittenTTS 用于英文朗读。小型运行时已经随安装包提供，大模型文件按需下载。打开“设置 -> AI 分析 -> 朗读”即可下载 Kokoro 或 KittenTTS。

朗读模型优先级会自动处理：KittenTTS 优先，其次 Kokoro。短词或短句会直接使用 Apple 系统语音。

运行系统要求：

- Kokoro 本地朗读需要 macOS 14.0 或更高版本。
- KittenTTS 本地朗读支持 macOS 12.0 Monterey 或更高版本。
- 主阅读器仍支持 macOS 12.0 Monterey 或更高版本。低于 macOS 14 的系统下载 Kokoro 时会先显示兼容性提示。

语音模型下载目前复用稳定的 `v1.5.10` 语音资源发布：

- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kokoro-coreml-macos-arm64.tar.gz`（Kokoro ANE/G2P 模型缓存）
- `https://github.com/dowellhz/LeafReader/releases/download/v1.5.10/kitten-tts-rs-macos-arm64.tar.gz`（KittenTTS mini 模型）

常规应用版本会复用这些模型文件。原生运行时二进制随应用打包；只有模型文件变化时才需要重新发布语音模型归档，并同步更新 `SpeechRuntimeResourceManager.Runtime.runtimeAssetsReleaseTag`。

生成语音模型包：

```sh
./scripts/package_speech_models.sh
```

## 1.6.1 更新

- 缩减安装包内置语音资源，只保留 KittenTTS 所需的 espeak 英文字典。
- 删除重复 Kokoro 英文声音，保留 Bella、Heart、Adam、Emma、George。
- 保持 KittenTTS 和 Kokoro 本地朗读在更小的 runtime 资源下正常工作。

## 开发

打开本地构建的 app：

```sh
open "Leaf Reader.app"
```

运行完整本地检查：

```sh
./scripts/check.sh
```

打包发布版本：

```sh
./scripts/release_pkg.sh 1.6.1
./scripts/publish_release.sh 1.6.1
```

发布流程、故障排查和代码地图见官网文档：<https://leafreader.space/manual/>

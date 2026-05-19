# 安装与入门

关键词：安装、下载、首次打开、AI 配置、API Key、PDF、EPUB、DOCX、翻译、背单词、更新。

## 下载与安装

1. 打开 [leafreader.space](https://leafreader.space/)。
2. 下载当前版本安装包。
3. 打开 `.pkg` 安装包并按提示安装。
4. 从“应用程序”启动 Leaf Reader。

当前版本安装包：

[LeafReader-1.4.14.pkg](https://github.com/dowellhz/LeafReader/releases/download/v1.4.14/LeafReader-1.4.14.pkg)

## 首次打开

- 使用书架导入最近阅读的书。
- 也可以直接打开 PDF、EPUB 或 DOCX 文件。
- Leaf Reader 会记录阅读位置，重新打开时恢复进度。

## 打开文档

支持格式：

- PDF
- EPUB
- DOCX

PDF 使用 PDFKit 阅读；EPUB 和 DOCX 会转换为本地 HTML 后在 WebKit 中阅读。

## 配置 AI

AI 功能不是必须项。未配置 AI 时，普通阅读、书架、翻页和基础文档打开仍可使用。

配置步骤：

1. 打开设置。
2. 选择聊天模型供应商和模型。
3. 填入 API Key。
4. 如需整本书问答或文档检索，配置 embedding 模型。
5. 运行连接测试。

API Key 保存在本机。只有使用 AI 功能时，选中的文本、问题或用于分析的片段才会发送到你配置的模型服务。

## 使用翻译和解释

1. 在书中选中文本。
2. 打开 AI 面板。
3. 选择解释、翻译、总结或继续追问。
4. 长文本翻译会自动分段处理。

## 使用背单词

1. 选中单词或短语。
2. 让 AI 解释含义。
3. 保存到本书背单词。
4. 在词汇面板中复习、查看上下文或导出。

## 检查更新

Leaf Reader 使用 Sparkle 更新通道。发布版本后，可以在应用内检查更新。

如果更新失败，先看 [故障排查](troubleshooting.md)。

## 相关页面

- [功能地图](feature-map.md)
- [AI Chat](ai-chat.md)
- [AI Analysis Cache](ai-analysis-cache.md)
- [Word Highlights](word-highlights.md)
- [Troubleshooting](troubleshooting.md)

# Leaf Reader Docs

Leaf Reader 的使用入门、工程文档、发布流程和故障排查入口。

## 文档状态

- 当前版本：`1.5.1`

<div class="hero-actions" markdown>

[返回官网](https://leafreader.space/){ .button .primary }
[下载 Leaf Reader](https://github.com/dowellhz/LeafReader/releases/download/v1.5.1/LeafReader-1.5.1.pkg){ .button }
[GitHub](https://github.com/dowellhz/LeafReader){ .button }

</div>

## 用户入口

<div class="grid" markdown>

[**安装与入门** - 下载、首次打开、AI 配置、翻译和背单词。](getting-started.md){ .card }

[**AI 使用** - 选中文本、翻译、解释、总结和追问。](ai-chat.md){ .card }

[**故障排查** - 更新失败、证书、翻页、AI 分析和 Wiki 同步。](troubleshooting.md){ .card }

</div>

## 开发者入口

<div class="grid" markdown>

[**功能地图** - 按产品功能找到对应代码。](feature-map.md){ .card }

[**开发任务** - 常见修改任务、入口文件和检查命令。](development-tasks.md){ .card }

[**代码地图** - 生成的模块摘要和大文件列表。](code-map.md){ .card }

[**发布流程** - 打包、签名、发布和 Appcast。](release-runbook.md){ .card }

</div>

## 文档分组

<div class="grid" markdown>

[**Architecture** - System shape and module boundaries.](architecture.md){ .card }

[**Getting Started** - Install, configure AI, and start reading.](getting-started.md){ .card }

[**Development Tasks** - Entry points for common engineering work.](development-tasks.md){ .card }

[**Code Map** - Generated module summary.](code-map.md){ .card }

[**Type Index** - Generated Swift type index.](type-index.md){ .card }

[**AI Chat** - AI panel actions, requests, and rendering.](ai-chat.md){ .card }

[**AI Analysis Cache** - Embedding cache and retrieval workflow.](ai-analysis-cache.md){ .card }

[**Word Highlights** - Vocabulary storage, review, and highlights.](word-highlights.md){ .card }

[**Security** - Secret handling and generated artifacts.](security.md){ .card }

</div>

## 常用命令

```sh
./scripts/check.sh
./scripts/build_docs_site.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
```

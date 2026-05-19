# Leaf Reader Docs

Leaf Reader 的工程文档、发布流程和故障排查入口。当前版本：`1.4.14`。

<div class="hero-actions" markdown>

[返回官网](https://leafreader.space/){ .button .primary }
[下载 Leaf Reader](https://github.com/dowellhz/LeafReader/releases/download/v1.4.14/LeafReader-1.4.14.pkg){ .button }
[GitHub](https://github.com/dowellhz/LeafReader){ .button }

</div>

## 快速入口

<div class="grid" markdown>

[**开发文档** - 架构、功能地图、开发任务入口。](feature-map.md){ .card }

[**功能模块** - 文档加载、AI、词汇和高亮。](document-loading.md){ .card }

[**发布流程** - 打包、签名、发布和 Appcast。](release-runbook.md){ .card }

[**故障排查** - 更新失败、证书、翻页、AI 分析和 Wiki 同步。](troubleshooting.md){ .card }

</div>

## 常用命令

```sh
./scripts/check.sh
./scripts/build_docs_site.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
```

## 文档分组

<div class="grid" markdown>

[**Architecture** - System shape and module boundaries.](architecture.md){ .card }

[**Development Tasks** - Entry points for common engineering work.](development-tasks.md){ .card }

[**Code Map** - Generated module summary.](code-map.md){ .card }

[**Type Index** - Generated Swift type index.](type-index.md){ .card }

[**AI Chat** - AI panel actions, requests, and rendering.](ai-chat.md){ .card }

[**AI Analysis Cache** - Embedding cache and retrieval workflow.](ai-analysis-cache.md){ .card }

[**Word Highlights** - Vocabulary storage, review, and highlights.](word-highlights.md){ .card }

[**Security** - Secret handling and generated artifacts.](security.md){ .card }

</div>

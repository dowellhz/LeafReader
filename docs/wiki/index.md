# Leaf Reader Docs

Leaf Reader 的使用入门、工程文档、发布流程和故障排查入口。

## 文档状态

- 当前版本：`1.7.4`

<div class="hero-actions" markdown>

[返回官网](https://leafreader.space/){ .button .primary }
[下载 Leaf Reader](https://github.com/dowellhz/LeafReader/releases/download/v1.7.4/LeafReader-1.7.4.pkg){ .button }
[GitHub](https://github.com/dowellhz/LeafReader){ .button }

</div>

## 中文文档

<div class="grid" markdown>

[**中文入口** - 中文使用说明、功能说明和开发入口。](zh.md){ .card }

[**安装与入门** - 下载、首次打开、AI 配置、翻译和背单词。](getting-started.md){ .card }

[**阅读笔记** - 选中文本生成笔记、AI 补全、问 AI 和 Markdown 编辑。](reading-notes.md){ .card }

[**背单词** - 单词保存、高亮、复习统计和导出。](word-highlights.md){ .card }

[**快捷键** - 阅读、翻页、搜索、朗读和笔记编辑快捷键。](shortcuts.md){ .card }

[**故障排查** - 更新失败、证书、翻页、AI 分析和 Wiki 同步。](troubleshooting.md){ .card }

</div>

## English & Engineering

<div class="grid" markdown>

[**English Index** - English entry points for features and engineering docs.](en.md){ .card }

[**Architecture** - System shape and module boundaries.](architecture.md){ .card }

[**Feature Map** - Find source files by product feature.](feature-map.md){ .card }

[**Development Tasks** - Entry points for common engineering work.](development-tasks.md){ .card }

[**Release Runbook** - Build, sign, publish, and verify releases.](release-runbook.md){ .card }

[**Code Map** - Generated module summary.](code-map.md){ .card }

[**Type Index** - Generated Swift type index.](type-index.md){ .card }

</div>

## 常用命令

```sh
./scripts/check.sh
./scripts/build_docs_site.sh
./scripts/release_pkg.sh <version>
./scripts/publish_release.sh <version>
./scripts/update_wiki.sh --push
```

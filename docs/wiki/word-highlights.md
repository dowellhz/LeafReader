# 背单词与单词高亮

关键词：背单词、词汇、复习、SRS、单词高亮、Anki CSV、导出。

Leaf Reader 会保存单词、解释、来源上下文和页面高亮，并在 PDF、EPUB、DOCX 等内容重新打开后恢复标注。

## 使用流程

```text
选中单词
  -> 查询 AI 或本地词典
  -> 保存单词记录
  -> 写入 SQLite
  -> 重新打开时恢复
     -> PDF 高亮
     -> Web 内容高亮
  -> SRS 复习和导出
```

选择超过一个单词时，不会检索本地词典，避免把短语误当成词条查询。

## 学习统计

背单词面板会显示当前书籍的学习概览：

- 总词数
- 今日已复习
- 已掌握词数
- 估算正确率
- 连续复习天数

估算正确率来自 SRS 的 review count 和 lapse count，是一个轻量进度指标，不是完整的逐次复习历史。

## 复习与数据

- `VocabularySRS` 负责复习间隔和掌握状态。
- 高频、待复习和当前书籍词汇会优先展示给用户。
- 单词详情里本地词典标签会和背单词标签复用，避免同一类标签在不同模块重复维护。
- 删除单词时，需要同时删除检索依据和关联元数据，避免气泡里删了但后台记录还存在。

## 存储与高亮恢复

- PDF 单词保存 page index 和 PDF bounds，用于恢复页面上的高亮位置。
- EPUB、DOCX 保存文本上下文、出现序号和滚动进度，用于在重新渲染后定位。
- Web 文本查找会归一化空白字符，提高 HTML 重新排版后的恢复成功率。
- SQLite schema 迁移使用 `SQLiteSchemaMigrator.ensureColumn`，只在列缺失时添加新列，避免依赖 duplicate-column 错误。

## 文件入口

- `ReaderWindowController+Vocabulary*.swift`：背单词 UI、动作、复习、导出和持久化入口。
- `ReaderWindowController+VocabularyHighlights.swift`：阅读区域单词高亮恢复。
- `ReaderWindowController+VocabularyReviewUI.swift`：复习界面。
- `ReaderWindowController+VocabularyReviewSRS.swift`：复习调度和状态更新。
- `WordRecordSQLiteStore.swift`：生产环境 SQLite 存储。
- `PDFWordRecordStore.swift` 和 `WebWordRecordStore.swift`：PDF/Web 词条模型和包装。
- `StoredPDFWordRect.swift`：PDF 高亮几何信息。
- `VocabularyLearningStats.swift`：当前书籍学习统计。
- `VocabularySRS.swift`：SRS 复习规则。
- `VocabularyExporter.swift`：Anki CSV 等导出。
- `mac-app/Resources/reader-web.js`：WebKit 选择、文本范围查找、单词高亮恢复和 AI 来源下划线恢复。

## 相关文件

- `mac-app/ReaderWindowController+Vocabulary.swift`
- `mac-app/ReaderWindowController+VocabularyHighlights.swift`
- `mac-app/ReaderWindowController+VocabularyReviewUI.swift`
- `mac-app/ReaderWindowController+VocabularyReviewSRS.swift`
- `mac-app/WordRecordSQLiteStore.swift`
- `mac-app/VocabularyLearningStats.swift`
- `mac-app/SQLiteSchemaMigrator.swift`
- `mac-app/VocabularySRS.swift`
- `mac-app/VocabularyExporter.swift`

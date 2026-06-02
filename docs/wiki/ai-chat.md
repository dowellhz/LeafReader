# AI 使用

关键词：AI、翻译、解释、总结、选中文本、追问、流式输出、气泡、API Key。

AI 面板负责选中文本解释、总结、翻译、继续追问，以及结合当前阅读内容的问题。没有配置 API Key 时，需要引导用户进入设置首页完成配置。

## 使用入口

- 选中文本后的浮动菜单：解释、翻译、总结、追问。
- 右侧 AI 面板：对当前内容总结、翻译，或继续追问。
- 单词气泡：可以请求 AI 解释单词；如果本地词典有标签，会追加到 AI 结果尾部，供背单词复用。
- 阅读笔记整理：把笔记内容发送给 AI 时，图片会用占位符保留位置，避免整理后图片丢失。

## 气泡行为

- 用户气泡和 AI 气泡按对话顺序显示。
- AI 气泡支持复制 Markdown；普通 AI 回答支持重新生成。
- 有来源的气泡可以回跳并高亮对应阅读位置。
- 气泡生成完成后，如果气泡 header 不在可视区域顶部，会滚动到 header，方便直接阅读结果。
- Markdown 内容由统一渲染器处理，避免复制、重新生成、恢复会话时样式不一致。

## 请求流程

```text
选中文本或当前阅读内容
  -> AIChatPanel 收集上下文
     -> Actions 组装用户动作
     -> Requests 管理请求生命周期
        -> AIClient 发送请求
        -> 流式增量返回
     -> Bubbles 渲染气泡
     -> Conversation 保存和恢复会话
```

## 文件入口

- `AIChatPanel.swift`：AI 面板核心状态和选中文本入口。
- `AIChatPanel+UI.swift`：面板布局、按钮和控件。
- `AIChatPanel+Actions.swift`：用户动作、选中文本问题、总结、翻译和追问上下文。
- `AIChatPanel+Requests.swift`：请求生命周期、重试、取消、翻译、忙碌状态和错误映射。
- `AIChatPanel+Selection.swift`：鼠标交互监听和气泡内文本选择。
- `AIChatPanel+Bubbles.swift`：气泡创建、渲染、布局节流和滚动定位。
- `AIChatPanel+Conversation.swift`：已保存对话的恢复。
- `AIChatPanel+LinkedWords.swift`：和单词记录关联的气泡行为。
- `AIChatPanel+Export.swift`：对话复制和导出。
- `AIConversationMarkdownExporter.swift`：对话 Markdown 导出格式。
- `AIClient.swift`：HTTP 请求和流式响应客户端。
- `AIPromptStore.swift` 和 `mac-app/AIPrompts.json`：内置提示词模板。

## 性能与维护

- 流式输出会先节流再刷新气泡，避免每个 token 都触发布局。
- 对话列表布局有 debounce，长对话不会在每次更新时完整重排。
- 最近会话会裁剪，限制启动和恢复气泡时的工作量。
- 涉及 API Key 的入口要统一走设置检查，避免不同按钮出现不同错误提示。

## 相关文件

- `mac-app/AIChatPanel.swift`
- `mac-app/AIChatPanel+Actions.swift`
- `mac-app/AIChatPanel+Requests.swift`
- `mac-app/AIChatPanel+Bubbles.swift`
- `mac-app/AIClient.swift`
- `mac-app/AIResponseTextFormatter.swift`
- `mac-app/AIPromptStore.swift`

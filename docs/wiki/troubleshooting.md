# 故障排查

关键词：更新失败、SSL 证书、GitHub Pages、Appcast、签名、公证、PDF 翻页、AI 分析、Wiki 同步。

这页记录 Leaf Reader 反复出现过的问题，以及改代码前应该先做的快速检查。

## 快速索引

| 现象 | 先看这里 |
| --- | --- |
| 更新检查拿不到信息 | [Sparkle 更新检查失败](#sparkle-更新检查失败) |
| 网站或 appcast 出现 HTTPS/证书错误 | [GitHub Pages SSL 或自定义域名问题](#github-pages-ssl-或自定义域名问题) |
| 打包、签名、公证或安装校验失败 | [安装包签名或公证失败](#安装包签名或公证失败) |
| PDF 滚动翻页太早、太晚或触发两次 | [PDF 翻页手感异常或重复触发](#pdf-翻页手感异常或重复触发) |
| 右下角 AI 分析状态过期或显示异常 | [AI 分析状态显示异常](#ai-分析状态显示异常) |
| AI 没返回，或单词一直走本地词典 | [AI 请求或网络状态异常](#ai-请求或网络状态异常) |
| 书籍、单词或笔记数据看起来没刷新 | [书籍或词汇记录看起来过期](#书籍或词汇记录看起来过期) |
| Wiki 无法 clone、pull 或 push | [Wiki 同步失败](#wiki-同步失败) |

## Sparkle 更新检查失败

现象：

- 更新弹窗提示无法获取更新信息。
- 已安装 app 仍然像是在使用旧的更新 URL。

检查：

```sh
curl -I -L https://leafreader.space/appcast.xml
curl -I -L https://dowellhz.github.io/LeafReader/appcast.xml
```

期望：

- 当前 appcast URL 返回 `200`。
- HTTPS 没有证书错误。
- `docs/appcast.xml` 里的 release URL 指向预期域名。

常见原因：

- 已安装 app 里还是旧的 `SUFeedURL`。
- GitHub Pages 自定义域名 DNS 或证书还在生效中。
- 本地更新了 appcast，但还没有推到 GitHub Pages。

## GitHub Pages SSL 或自定义域名问题

检查：

```sh
dig leafreader.space
dig www.leafreader.space
curl -I -L https://leafreader.space/
```

期望：

- `docs/CNAME` 包含规范自定义域名。
- DNS 指向 GitHub Pages。
- GitHub Pages 设置里 HTTPS 可用并已强制开启。

如果证书错误或缺失，在仓库 Pages 设置里移除并重新添加自定义域名，然后等待 GitHub 重新签发证书。

## 安装包签名或公证失败

检查：

```sh
./scripts/check.sh
security find-identity -v
pkgutil --check-signature release/pkg/LeafReader-<version>.pkg
```

常见原因：

- 当前 keychain 里缺少 Developer ID 证书。
- 本地 keychain profile 里没有公证凭据。
- 复用了上一次构建留下的 release 产物。

## PDF 翻页手感异常或重复触发

相关文件：

- `mac-app/PDFReaderView.swift`
- `mac-app/PDFPagingPolicy.swift`
- `mac-app/ReaderWindowController+Navigation.swift`

检查：

- 确认边缘翻页只在页面顶部或底部触发。
- 保留 PDFKit 原生滚动行为，不要拦截正常滚动。
- 降低阈值前，先确认重复翻页 cooldown 是否生效。

## AI 分析状态显示异常

相关文件：

- `mac-app/ReaderWindowController+EmbeddingStatus.swift`
- `mac-app/ReaderWindowController+EmbeddingActions.swift`
- `mac-app/ReaderWindowController+Theme.swift`
- `mac-app/PDFEmbeddingStore.swift`

检查：

- 状态标签只应在索引中、暂停、失败、取消或缓存状态提示时显示。
- 主题切换后，要重新应用预期的状态文字颜色。
- 当前文档如果已有缓存 chunks，界面应该显示缓存状态，而不是继续显示旧的分析中状态。

## AI 请求或网络状态异常

现象：

- 明明网络可用，单词查询仍然一直走本地词典。
- 中途断网后，其他 AI 请求已经成功恢复，但单词侧仍然认为不可用。
- 没有配置 API Key 时，某些 AI 入口没有跳到设置首页。

检查：

- API Key、Base URL 和模型是否在设置页配置完整。
- 失败后是否进入了本地词典 fallback。
- 如果其他 AI 请求成功返回，应恢复全局网络可用状态。
- 如果单词侧认为只能用本地词典，有网络时后台按间隔测试设置页 AI 连接；成功后停止测试，直到下一次请求失败。

相关文件：

- `mac-app/AIClient.swift`
- `mac-app/AISettingsPanelController.swift`
- `mac-app/ReaderWindowController+VocabularyActions.swift`
- `mac-app/ReaderWindowController+VocabularyLookup.swift`

## 书籍或词汇记录看起来过期

相关文件：

- `mac-app/DocumentIdentity.swift`
- `mac-app/WordRecordSQLiteStore.swift`
- `mac-app/PDFEmbeddingStore.swift`
- `mac-app/ReaderWindowController+VocabularyStorage.swift`
- `mac-app/ReadingNoteStore.swift`

检查：

- 文档 ID 对同一个文件是否稳定。
- 文件是否移动、大小是否变化、修改时间是否变化。
- 词汇问题先检查 word record store，不要直接删除用户数据。
- 阅读笔记问题先检查 note id、source id 和图片附件占位符是否一致。

## Wiki 同步失败

命令：

```sh
./scripts/update_wiki.sh
./scripts/update_wiki.sh --push
```

常见原因：

- `/private/tmp/leafreader-wiki-sync` 下的 GitHub Wiki worktree 有意外本地改动。
- 当前网络或 GitHub SSH/HTTPS 访问不可用。
- 上次同步后修改了 `docs/wiki` 源文件，但还没有提交到主仓库。

先用 dry-run 模式检查。push 模式会更新 GitHub Wiki，并把变更后的 `docs/wiki` 文件提交回主仓库。

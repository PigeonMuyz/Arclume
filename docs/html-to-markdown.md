# 公告正文解析

`HTMLToMarkdown` 是独立的离线 HTML → Markdown 转换器；`JX3HTMLToMarkdown` 在它上面添加剑网 3 公告的排版规则。使用 SwiftSoup 2.13.9（MIT）构建 HTML DOM，自有转换层输出 Markdown，不改变 `SteamTextFormatter` 的纯文本行为。

```swift
let markdown = try HTMLToMarkdown.convert(html, baseURL: articleURL)
let jx3Markdown = try JX3HTMLToMarkdown.convert(html, articleURL: articleURL)
```

## 层次

1. 数据源获取标题、日期、文章 ID、来源 URL 与 HTML 正文。
2. 转换器接收正文片段，输出 Markdown，不负责请求、缓存或整页正文提取。
3. 展示层根据 Markdown 结构应用自己的标题、段落、列表与图片样式。

其他数据源实现 `HTMLMarkdownRule`，通过 `rules` 参数传入；规则只处理没有嵌套块级内容或媒体的独立段落，不修改原始 DOM。不要通过通用层硬编码网站名。

## 支持与边界

- 支持 HTML 片段/文档、实体、标题、段落、硬换行、粗体/斜体/删除线、链接、图片、有序/嵌套列表、引用、代码块、基础 GFM 表格。视频/音频降级为链接。
- 保留内容，默认丢弃网页颜色、字体、字号、脚本与嵌入控件。带跨行/跨列或嵌套的表格保留文字降级，不承诺复现复杂 HTML 布局。不支持 CSS 排版、脚注或数学公式。
- 正文阅读可显式开启 `preserveTextColors`，仅将校验后的前景 RGB 色值转换为受控 `span` 扩展；这是带颜色的 Markdown，不是默认纯 Markdown 输出。不会保留任意 CSS 或网页标签。
- SwiftSoup 显式使用 HTML parser 容错解析，保留 HTML5 正文节点与实体；不执行浏览器渲染。解析错误直接抛出，不用空正文伪装成功。
- 不执行脚本，不读取 HTML 的 `base` 标签，不加载图片或任何外部资源；相对 URL 只使用调用方提供的 `baseURL`。图片只允许 HTTP(S)，链接另允许 mailto，拒绝本地文件、脚本、data URL 与含凭据的 HTTP URL。
- 默认最多 2 MiB 输入、50,000 节点、128 层。字节限制在解析前执行，节点与深度限制在 DOM 构造后、Markdown 遍历前执行，后两项不是 DOM 构造的内存限制。不是流式转换器；应在后台按需处理单篇文章，不能批量把整个新闻库正文一起转换。
- 默认输出不含原始 HTML，但显示端仍须控制远程图片下载与打开链接的行为。Markdown 不是任意渲染器的安全沙箱。

## 剑网 3 数据源

官方入口 `https://jx3.xoyo.com/api.php?op=search_api`：

| 类型 | action 与参数 | 正文 |
| --- | --- | --- |
| 公告 | `get_customer_article_detail&game=jx3&kid=公告ID` | `data.content` |
| 新闻 | `get_article_detail&catid=栏目ID&id=文章ID` | `data[0].content` |

`JX3ArticleContentService` 在点击公告时按需请求上述官方详情接口，限制响应为 4 MiB、请求为 30 秒，支持关闭时取消，并在后台调用转换器。公告返回对象、新闻返回数组，优先读取 `content`，兼容 `contentHTML`。转换器本身仍不负责网络请求。

标题/日期等元数据独立保留，不重复拼入正文。剑网 3 扩展把短的 `【…】` 转为二级标题、`◎ …` 转为三级标题、短蓝色 `1、…` 转为四级标题、`·`/`•` 开头条目转为列表。其余内容按通用规则处理，未来官网格式变化时只调整此扩展。

`LauncherNewsPanel` 提供轮播与公告卡片入口，`LauncherAnnouncementView` 保留原文入口、关闭和失败重试。正文在后台使用 cmark-gfm 0.9.0 解析并生成 HTML，经 SwiftSoup 标签/属性白名单净化、RGB 对比度调整后交给 `AnnouncementReaderBody` 排版，避免一次创建整篇 SwiftUI 文本树。WebKit 使用临时数据存储，禁用 JavaScript，CSP 禁止脚本、表单、框架与非图片资源，不直接加载官网页面。

调试构建的 `announcement-reader` 隔离场景默认使用自编正文，不访问用户容器或启动游戏。仅显式设置 `ARCLUME_ARTICLE_LIVE_FIXTURE=1` 才从官网按需读取真实长公告。核心测试可用 `ARCLUME_ARTICLE_TEST_JSON` 指定本地官网响应，数据不随项目提交。

测试使用人工构造的离线样例，不依赖实时官网或用户游戏库。

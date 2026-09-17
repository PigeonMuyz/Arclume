# 游戏展示资料与内置适配

## 资料来源

“更多 → 编辑项目信息 → 匹配资料…”支持 GameDB（LizardByte 托管的 IGDB 静态资料）与单个 Steam 商店条目。GameDB 不需要用户密钥，不读取 Steam 账号拥有的游戏清单。

GameDB 查询只发送名称前缀桶与选中的游戏 ID，不发送本地路径、容器配置或账户信息。匹配结果由用户预览并确认。GameDB 的精确 Steam 映射用于请求当前 Arclume 语言的商店名称与简介；无映射、网络失败或缺少本地化时回退到原始资料，不自动翻译。中文名字查不到时可用英文原名查询，或使用 Steam 商店链接。

采用的内容先进入编辑草稿，保存时才写入 `projectPresentations.v1`。该记录包含来源 ID 和查询语言；手动采用的快照不会随语言切换自动覆盖。已有 GameDB 关联的后台刷新则按语言与缓存有效期进行。所有展示更新都不改变 Game ID、Steam 启动 ID、可执行文件、容器、运行时或安装状态。

## 内置 JSON 适配

文件：`Arclume/Resources/game-profiles.json`，随应用打包。格式示例：

```json
{
  "schemaVersion": 1,
  "profiles": [{
    "id": "example",
    "gameIDs": ["custom.example"],
    "executableNames": ["ExampleGame.exe"],
    "localized": {
      "zh-Hans": { "name": "示例游戏", "summary": "简短介绍" },
      "en": { "name": "Example Game", "summary": "Short description" }
    },
    "backgroundURL": "https://example.com/background.jpg",
    "logoURL": "https://example.com/logo.png"
  }]
}
```

Game ID 或可执行文件名精确匹配（文件名忽略大小写）；优先使用唯一 Game ID，共享启动器不得用宽泛文件名规则。名称仅替换空值或已知官方名称，不覆盖用户自定义名称。用户手动图片覆盖优先于 JSON，其次为官方图片与已有游戏元数据。

可选 `artworkProvider: "jx3-official"` 使用已经审核的剑网3官方背景/标志读取器；不是轮播图。未知 provider 不执行任何动态代码，只使用静态 URL 与通用元数据。新增动态资讯源仍需实现并审核读取器，JSON 不接受脚本、启动参数或注册表操作。

## 验证与回滚

- `ProjectPresentationTests` 覆盖身份隔离、JSON/旧数据兼容、本地化回退与图标色提取。
- 手工检查 JX3/原生/Windows 的更多菜单、编辑器左右布局与图片预览、资料匹配弹窗、取消不落盘、运行设置以及设置各分区。
- 恢复旧 App 即可回滚 UI；新展示键会被旧版忽略。没有迁移、删除或改写容器文件。无需清空 Application Support。
- 原生警告、文件选择器仍由 macOS 展示；安装/迁移进行中保留禁止关闭的安全约束。

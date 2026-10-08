# 项目目录

## 源码

```text
Arclume/
├── App/                    App 入口、生命周期、场景和模式状态
├── Features/
│   ├── Launcher/           启动器、侧边栏、手柄栏、工具栏
│   ├── Library/            游戏库页面与展示
│   ├── Onboarding/         首启、升级、可选初始化；Tour 为功能教学
│   ├── Settings/           设置、工具、组件下载
│   ├── ProjectEditor/      项目信息、图片、资料匹配、运行设置
│   ├── Import/             原生应用、便携应用和 Windows 安装器
│   └── JX3/                剑网 3 图形与附加设置
├── Components/Shared/      跨功能复用的基础 UI
├── Models/                 共享模型和现有全局状态类型
├── Services/
│   ├── Runtime/            Wine 安装、配置、进程停止与预热
│   ├── Resources/          组件目录、依赖、下载与进度
│   ├── Migration/          容器迁移、旧目录识别与重置
│   ├── Launching/          应用启动、麦克风授权和 YY 适配
│   ├── Library/            发现、扫描缓存、排序、移除与适配规则
│   ├── Metadata/           GameDB、Steam、App Store 资料
│   ├── Presentation/       图标、颜色、外观和项目编辑草稿
│   ├── Steam/              Steam 安装、容器、本地游戏库发现
│   ├── JX3/                配置预设、GPU 配置、资讯和启动器图片
│   ├── Import/             归档导入、便携程序、Windows 安装
│   ├── Input/              手柄输入
│   ├── Onboarding/         引导布局
│   ├── Updates/            App 更新来源、下载和安装
│   └── Diagnostics/        日志
├── Support/                文件、配置、偏好、本地化等基础工具
│   └── Testing/            隔离测试宿主和迁移预览
├── Resources/              随包资源、适配 JSON 和组件清单
├── Assets.xcassets/         图标与颜色
└── Arclume.xcdatamodeld/    Core Data 模型
```

`ArclumeTests/` 按 App、Launcher、Library、Launching、Runtime、Resources、Migration、Steam、Metadata、JX3、Import 分组。`ArclumeUITests/` 保留独立 UI 测试目标。

## 文件放置规则

- 页面及其专属视图放入 `Features/<功能>/`；只有跨功能复用的基础组件放入 `Components/Shared/`。
- 非 UI 的行为放入 `Services/<领域>/`；共享模型放入 `Models/`；基础工具放入 `Support/`。不再恢复平铺的 `Util/`。
- 本次只组织文件，不拆分现有 `Types.swift` 等混合职责文件；它们的逻辑重构应单独进行。
- Xcode 使用同步目录组，源码和测试仍在原 target 根目录内；新文件通常不需要手动修改 `project.pbxproj`。不要把文档或构建产物放入同步源码目录。
- `Info.plist`、entitlements、xcconfig、字符串表和资源目录保持原位置，避免改变构建、加载、迁移或发布协议。
- 历史 Procyon 路径、偏好键和 Runtime 协议标识如仍被兼容逻辑使用，不能作为品牌残留直接替换；许可证与作者归属同样保留。

## 工程辅助目录

| 目录 / 入口 | 用途 |
| --- | --- |
| `design/` | 可编辑图标设计源文件，不参与 App 打包。 |
| `script/build_and_run.sh` | 本地构建、运行和诊断入口。 |
| `script/pr_preflight.sh` | 静态检查、无签名 Debug 构建及资源边界检查。 |
| `script/*resources.py` | 组件归档准备、上传和保留策略；上传需明确授权。 |
| `script/diagnostics/` | 专项诊断工具，不会在常规构建中执行。 |
| `script/tests/` | 发布与对象存储脚本的离线测试。 |
| `docs/` | 开发、协议、测试、发布与使用说明。 |
| `CHANGELOG/` | 追加式变更记录，历史条目不因目录整理而重写。 |
| `build/`、`DerivedData/` | 忽略的本机构建产物、测试结果与临时打包目录。 |

为保持现有 CI 与本地命令兼容，脚本入口不搬动。`Resources/OnlineGameDependencies/`、`Libs/` 的资源、归档和 Manifest 本次不移动或改写；本机旧构建、应用备份和用户数据不清理。

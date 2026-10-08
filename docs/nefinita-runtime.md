# Nefinita 运行时兼容

Nefinita 为暂定显示名称，对接 `nefinita/mac-gamestater` 的运行时构建流程。
当前固定提交：`cadaabf0705efa677e4683a2af86d1da3316e8bb`，运行时版本 `0.3.0`。

## 用户流程

设置 / 初始化中的运行时选项：

- 下载编译好的 Arclume Runtime：保留原下载、验证和安装链路。
- 在本机编译 Nefinita：检查工具，确认后自动获取构建材料，再准备 Wine 源码、构建依赖、应用 FineWine 补丁、编译并安装。不要求用户选择源码目录。

构建材料优先使用已配置的 OSS，网络获取失败时回退到 GitHub 固定提交的原始文件，而非克隆全部历史或执行最新分支代码。支持的 13 个输入文件及 SHA-256 位于 `nefinita-build-recipe.json`；最多并发下载 3 个文件，下载落盘后校验，再复制到独立工作目录并重新校验。有效缓存可直接复用。
上游仍为私有仓库，匿名 GitHub 回退无法获取它们；应用使用 OSS 已发布的固定构建输入，不要求用户找源码目录，也不会使用开发者的 GitHub CLI 或凭据。未配置下载地址的开发包仍不能使用私有 GitHub 回退。
应用不编译自身仓库中的 Wine，不携带或复制上游构建脚本，只有已验证外部构建输入可执行。

## 环境与日志

需要 Command Line Tools、Rosetta 2（Apple Silicon）、Bison 3+、CMake、Meson、Ninja、pkg-config、Python 3、MinGW 工具。
检查器不会自动安装系统工具；Rosetta 缺失会在准备界面显示，需用户通过 macOS 安装。
工具可放在 Arclume 的 `BuildTools/bin`，也兼容已安装的 Homebrew 工具；不会修改系统 PATH。
构建仅传递必要环境变量，默认本机临时签名，不要求用户持有开发证书。
最多使用 4 个构建并发任务。构建输出写入 `RuntimeBuilds/Nefinita/<会话>/build.log`，不把大量输出载入内存。
实际编译工作区位于无空格的物理缓存目录 `Library/Caches/Arclume/RuntimeBuilds/Nefinita/<会话>`；用户目录含空格或不受构建工具支持的字符时改用系统临时目录。日志第一行记录工作区，旧会话不搬迁。不能使用指向 `Application Support` 的软链接规避空格，因为构建工具可能再次解析物理路径。
构建期间暂不支持中止当前阶段；关闭设置不会取消构建。编译失败保留该会话用于诊断，再次构建创建新会话。

## 共享容器与运行时切换

- Arclume 和 Nefinita 都使用 `Application Support/Arclume/ALBottles`。游戏、注册表、存档与已保存的启动路径不因选择运行时而迁移，不再创建 `NefinitaBottles`。
- 两套 Wine 文件仍安装在各自的版本化目录，保留各自 Manifest 和上游 ABI 标识，不伪造或修改为相同 ABI。共享容器是 App 针对这两套固定运行时的路由策略，不代表任意版本可互换。
- 切换动作只更改引擎偏好，不执行 wineboot，不复制或改写容器。下次启动、安装程序和预热均使用所选引擎访问同一容器。
- 切换前在后台关闭启动入口并撤销排队中的旧启动请求，再确认两套受管 Wine 均无存活进程（包含预热和 wineserver）。有进程时提示先结束容器运行，不自动关闭用户游戏；检查或就绪验证失败保持原选择。
- 新运行时仅在构建和产物检查通过后可启用。两套引擎已就绪时可来回选择，不需重复下载或编译。
- 尚未完成真实 Wine 的双向切换验收。首次用不同引擎启动时，Wine 自身可能更新注册表和内置 DLL；切回原引擎不等于回滚这些数据。需要在隔离测试容器中验证 Arclume → Nefinita → Arclume，以及 32/64 位应用、Steam 和剑网 3 后再用于发布。
- 当前只接入 D3DMetal 图形路径，不把 Arclume 自带 DXVK 当作 Nefinita 必需文件。Nefinita 自带 GStreamer，不下载 Arclume 的单独 GStreamer 包。

## OSS 发布边界

### CodeWeavers 开源源码镜像

`nefinita-wine-source.json` 固定 26.3.0 原始开源源码归档（149,054,023 字节），来源为官方 FOSS 源码，不是 CrossOver 商业安装包。保留整个原始归档及其中的许可文件，不重新打包。

对象路径为 `components/source/codeweavers-wine/org.codeweavers.wine-source/26.3.0/<SHA256>/crossover-sources-26.3.0.tar.gz`。App 优先使用配置的 OSS，网络失败回退官网；哈希错误直接拒绝，不默默换源。`~/Library/Caches/Arclume/BuildSources/<SHA256>/` 保存已校验归档，跨构建会话复用；准备后复制至独立构建目录供原脚本再次校验，不修改已签定的 13 个输入文件。

发布：`python3 script/publish_nefinita_wine_source.py --archive <本地原始归档>` 默认只检查，追加 `--execute` 才上传。仅增加这一不可变对象，不发布 DMG、不执行远端清理。源码缓存可由系统回收，回收后会重新下载；不改变旧 App 的官方源行为、运行时 ABI 或用户容器。

### 固定构建配方

维护者已批准发布该固定版本的 13 个构建输入，合计 57,662 字节；没有上传整个仓库、编译工具包、Wine 构建产物或 DMG。工具包和其他源码镜像仍需后续准备。
构建输入的准确对象路径为 `components/build-recipe/nefinita/dev.nefinita.build-recipe/<版本>-<提交前8位>/<文件SHA256>/<runtime内相对路径>`，例如相对路径 `script/build-runtime.sh`。下载根地址复用 App 的 `ArclumeResourceBaseURL`，界面不展示服务器地址。
保留现有 `components/类型/名称/ID/版本/SHA256/文件名` 结构，工具需区分宿主架构；发布配方应包含全部源码版本、补丁、工具版本和哈希。
不要把私有仓库改为匿名动态脚本入口，也不要把开发者的 Homebrew 整个目录复制给用户。

发布命令：`python3 script/publish_nefinita_recipe.py` 获取并校验固定输入，默认只本地暂存；`--execute` 才上传。复用现有发布工具的环境变量、容量检查和排他锁，只增加缺失对象并校验远端及匿名 HTTPS 下载；不删除任何远端对象。回执位于 Git 忽略的 `build/resource-upload/nefinita-recipe-upload-report.json`。

本地 App 下载地址仅写入 Git 忽略的 `Arclume/Config.local.xcconfig`，不包含上传凭据。可使用 `swift script/verify_nefinita_recipe.swift <App路径>` 验证成品配置和 macOS URLSession 匿名下载，不执行构建脚本。

## 验证

核心测试：`NefinitaRuntimeTests`、`NefinitaSourceServiceTests`，使用独立偏好及临时目录，不下载或编译 Wine，不触碰真实容器。下载测试注入本地文件，覆盖 OSS 失败回退、固定提交与路径约束、缓存复用、错误哈希拒绝及下载失败不产生就绪缓存。
完整 Wine 构建、游戏运行、OSS 工具准备和 UI 真机验收需单独执行，不能用 App 编译通过替代。

2026-09-24 本次验证：

- `./script/pr_preflight.sh`：通过无签名 Debug build、资源打包边界和发布静态检查。
- `xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -only-testing:ArclumeTests/NefinitaRuntimeTests -only-testing:ArclumeTests/BundledWineRuntimeTests -only-testing:ArclumeTests/ResourceRuntimeCompatibilityTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`：20 项通过。覆盖同路径引擎路由、往返切换、启动门禁、失败不改变偏好与保留容器文件。
- 修正旧测试对 1.0.0 的写死断言，改为校验运行时清单及其版本与归档名的一致性；未改变现有 1.1.2 清单。
- `git diff --check`：通过；未运行 UI XCTest、上传资源、发布或覆盖 Applications。

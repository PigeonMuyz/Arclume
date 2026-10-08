# 运行组件下载分发

App 只携带组件目录与校验值，不携带 Wine、D3DMetal、DXVK、媒体库等运行二进制。已有容器不搬迁；首次设置和设置页由用户主动点击下载。普通游戏启动不静默下载。

## 已确认的对象结构

- `components/<type>/<name>/<id>/<version>/<sha256>/<filename>`：按组件类型、名称、稳定 ID、版本分类；内容寻址、不可覆盖。
- `apps/arclume/<版本>-<构建号>/<sha256>/<filename>`：DMG 及校验文件；同时发布到 GitHub。
- `catalogs/<App版本>-<构建号>/resources.json`：对应发布的固定清单。
- `catalogs/<App版本>-<构建号>/THIRD-PARTY-NOTICES.md`：随该版组件清单发布的第三方声明；本地暂存时另按 `licenses/<id>/<version>/` 分组，各归档保留其原许可证。

此结构已由维护者确认；只有正式发布阶段才使用上传密钥。更改分发位置并不改变第三方组件的许可条件；发布者仍须审核各组件的分发权限，不把闭源组件声明为 GPL。

## 容量与版本保留

桶配额为 15 GiB。Arclume 本体保留最近两个发布版本（版本号与构建号共同标识）；每种运行时按稳定 ID 分别保留最近三个版本。预编译包与将来的本机构建配方属于同一种运行时的不同交付方式，而不是混在一起按文件数量计数。

上传前统计桶内全部对象与本次新增大小；超出配额则停止并报告，不先删除旧版本腾空间。新文件上传、下载校验和不可变发布清单写入全部成功后才允许清理。删除必须由有效发布清单生成精确对象计划；缺失或无法解析清单时停止清理，未受管理的对象不删除。

已发布 App 默认仍受支持，即使 DMG 超过两个版本已被清理，其固定清单和组件引用仍纳入兼容保护。运行时最近三个版本为常规保留下限，旧版受支持 App 需要的更早版本不能删除，也不能重定向到不同 SHA 的新版。将来终止某版兼容支持须维护者单独明确批准，不由此工具自动执行。因此兼容性保护可能使运行时超过三个版本；达到配额时必须停止并请维护者决策。

保留规则仅针对 OSS，不删除 GitHub Release、本机下载缓存或用户容器。计划默认只预览；实际执行需发布命令显式启用清理。

## 准备和配置

`python3 script/prepare_downloadable_resources.py --write-catalog` 只准备 `build/resource-upload/` 并更新 App 内无 URL 的固定清单，不访问服务器。常规发布不带 `--write-catalog`，必须与已审核清单逐项一致。组件 SHA-256 流式计算，不把完整归档载入内存。

`python3 script/upload_resources.py --dmg <DMG文件> --app-version <项目版本> --app-build <构建号>` 默认只校验本地文件并生成计划，不访问 OSS。加 `--execute` 才上传，上传后会通过 S3 和公开 HTTPS 下载入口分别流式校验。`--execute --apply-retention` 仅在全部发布对象校验完成后执行保留计划。DMG 的校验文件随 DMG 淘汰，声明与兼容清单随受支持组件保留。不可变索引保存在 `indexes/apps/arclume/<版本>-<构建号>.json`，不自动删除。

CLI 只从环境读取 `AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`、`AWS_DEFAULT_REGION`、`AWS_ENDPOINT_URL`、`ARCLUME_RESOURCE_BUCKET` 和 `ARCLUME_RESOURCE_BASE_URL`。CI 对应的 Secret 为 `ARCLUME_OSS_ACCESS_KEY_ID`、`ARCLUME_OSS_SECRET_ACCESS_KEY`、`ARCLUME_OSS_REGION`、`ARCLUME_OSS_ENDPOINT_URL`、`ARCLUME_RESOURCE_BUCKET`、`ARCLUME_RESOURCE_BASE_URL`。不把本地 env 文件复制进仓库。发布报告保存在 `build/resource-upload/publish-report.json`，不含密钥或服务器地址。

GitHub 发布工作流串行执行：准备资源 → 构建单 DMG → 上传并校验 OSS → 发布 GitHub → 执行兼容保留计划。CLI 另有本机排他锁，但它不是跨机器锁，禁止在 GitHub 发布期间手动并行上传或清理。Garage 与 AWS 的条件写入支持不同，不能只靠 `If-None-Match` 当作分布式锁；参见 [Garage S3 实现](https://github.com/deuxfleurs-org/garage/blob/main-v2/src/api/s3/put.rs)。对象内容冲突、索引无效、配额不足、版本化桶或清理前索引变化时均停止，不尝试覆盖旧对象。

构建设置 `ARCLUME_RESOURCE_BASE_URL` 由本地忽略的 `Arclume/Config.local.xcconfig` 或 CI Secret 注入 Info.plist 的 `ArclumeResourceBaseURL`。xcconfig 中 HTTPS 的双斜线需写为 `https:/$()/...`。未配置地址的开发包仍可构建，但下载会提示服务未配置；发行流水线必须拒绝空地址。源代码、提交、用户提示和错误消息不包含服务器 IP 或访问凭据。

基础下载 URL 不是访问密钥，安装包和网络请求中必然可观察到该地址；不得把 S3 写入密钥放入 App。TLS 校验始终开启。上传密钥只在受信发布环境读取，不能供 PR 构建使用。禁止公开发布含凭据的 env 文件。

## 安装、兼容与后续扩展

### 只预上传运行组件

`python3 script/upload_resources.py --components-only` 只生成本地计划；加 `--execute` 上传已暂存的运行组件和 `licenses/<id>/<version>/THIRD-PARTY-NOTICES.md`，不需要 DMG，不创建 App 发布索引，也不执行保留清理。该模式拒绝混用 DMG、App 版本或清理参数。可用 `--report build/resource-upload/component-upload-report.json` 单独保存每个已验证文件的回执，正式发布后仍通过 App 索引登记组件引用。

### 引导与测试

教学结束后可选择升级运行时／补全第三方组件，未选择 Steam 或剑网3 也能进入此页；仅使用 Mac 应用可以稍后配置。提示仅依据当前用途的必需组件，不因可选组件未下载而阻挡继续。设置和引导均提供组件独立下载入口，下载前确认项目、体积与并行方式。已安装当前版本 Wine 时不重复下载 Wine 归档。

`requirements` 将依赖绑定到精确的 `runtimeID` / `runtimeVersion`，无声明或版本不匹配时不能套用其他引擎的依赖。Wine 1.1.2 自身只需 Wine 归档；Steam / 剑网3初始化另需当前 Mac 支持的默认 D3DMetal（3 或 4，只下载一种）和字体；NVNGX 单独可选。组件清单中的历史 DXMT、GStreamer、兼容修补归档继续保留供旧版兼容，但不属于当前运行时可选择的组件。App 已移除 CrossOver 修补能力，不再复制、重签或替换用户 CrossOver 中的文件。

组件下载和分段请求共享最多 3 路网络连接。大于等于 24 MiB 的文件只在 HEAD 确认 `Accept-Ranges: bytes` 且长度匹配时分成三段；不支持时降为普通单流。每段必须返回精确的 206 / Content-Range 和片长，不能把 200 响应拼接。分片以不超过 1 MiB 缓冲合并，最终仍核对完整归档 SHA。总进度按字节计量，速率显示本批次平均值；200ms 节流避免拖慢界面。失败取消剩余请求，已经成功的组件保留供重试复用。

Debug 隔离演示使用 `ARCLUME_UI_TEST_FIXTURE=1`、唯一 UUID 的 `ARCLUME_TEST_RUN_ID`，场景 `ARCLUME_UI_TEST_SCENARIO=live-tour` 为完整教学，`resource-upgrade` 直接展示升级和补全，`resource-retry` 展示一次失败再重试。演示使用内存状态，不实际下载、升级或初始化用户容器；真实下载须在正常运行的 App 中由用户点击。

下载写入临时文件，验证长度与固定 SHA-256 后进入内容寻址的暂存目录，成功才写完成标记。失败不覆盖已完成组件；损坏的未完成目录留作隔离，用户容器不动。Wine 沿用既有 staging/原子替换与 ABI 校验；有进程使用运行时则拒绝更换，用户自行结束后重试。

清单独立记录组件类型、名称、ID、版本、架构、Runtime ABI、Prefix ABI 和引擎来源，并区分 `precompiled` / `localBuild` 交付策略。运行时选择支持 Arclume Wine 预编译包和固定版本的 Nefinita 本机构建，不开放任意脚本或运行时替换。Nefinita 的自动材料获取、工具要求、共享容器限制及尚未完成的发布步骤见 [Nefinita 运行时兼容](nefinita-runtime.md)。

App 加载下载清单时还会与其内置 Runtime Manifest 完整匹配（包括版本、架构、两个 ABI、归档名与 SHA）。不匹配即拒绝安装，不尝试用“最新版”兜底。历史 GitHub Release 及旧 Runtime 下载地址不在 OSS 清理范围内，已有本地环境和归档仍按原路径兼容。

回退旧 App 不删除已下载组件或容器；本次不清理源码归档或 LFS 历史。需要从 Git 历史删除二进制属于另一个须明确批准的破坏性任务。

## 发布验收

1. 维护者确认目录结构、组件许可证及本次清单后，才允许上传。
2. 先上传不可变组件及 DMG，再验证下载长度及 SHA-256，最后上传发布清单；禁止覆盖旧对象。按保留计划清理过期对象前，重新核对引用和容量。
3. 打包只生成 `Arclume-<版本>.dmg`，检查 App Resources 无运行组件归档、Libs、DLL、SO 或第三方 dylib 残留。
4. 真机覆盖首次下载、断网重试、校验失败、已安装复用、Wine 运行中拒绝更换和旧版迁移后启动。未执行的检查不得标记通过。

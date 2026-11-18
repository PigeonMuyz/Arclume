# 增加资源发布保留规划

- 发布索引按 App 版本与构建号记录 DMG、资源 catalog、组件对象及 Runtime ABI、Prefix ABI 和架构；Runtime 清单摘要必须匹配对应组件。
- 保留规划仅根据可验证的发布索引生成精确对象计划。DMG 保留最近两个 App 发布；仍受支持的旧版索引继续保护其 catalog、第三方声明和组件，未登记对象不会进入删除计划。
- 可选 App SHA-256 sidecar 与 notice 使用固定路径校验；最近两个 App 发布保留全部对象，旧版支持期只继续保留 notice，sidecar 随 DMG 淘汰。
- 每个 Runtime ID 独立统计最近三个版本；旧版兼容引用可以继续保留更早组件，并在计划中报告兼容保护对象及其体积、实际保留对象数和体积。
- Runtime 选项仅接受 `precompiled` 策略，且选项 ID 与策略组件 ID 必须引用本索引中由 Runtime manifest 验证的组件。
- 缺少索引时不清理；无效索引或不明确的 `supported` 字段会阻断整个删除计划。发布和实际清理需通过独立命令及显式参数执行。
- 上传工具默认只生成本地计划，执行时检查 15 GiB 配额、固定组件散列和公开下载结果，最后写入不可变索引；清理前复核索引和精确对象。CI 串行发布、本地排他锁避免同一入口并发发布，不将服务器地址或密钥写入源码和报告。
- 验证：`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s script/tests -p 'test_resource*.py'`，保留规划 13 项、上传准备 3 项，共 16 项通过。未连接对象存储、未上传或删除远端对象。

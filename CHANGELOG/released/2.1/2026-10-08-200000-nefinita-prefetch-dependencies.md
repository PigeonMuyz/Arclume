# Nefinita 全部构建材料并发预取

- 构建前统一获取 Wine、21 个锁定依赖归档与 FineWine 固定补丁，共 23 份材料；最多三路并发，显示完成数量、字节量及下载速度，全部校验成功后才开始源码准备与编译。
- 全部材料优先使用 OSS，传输失败有限重试后回退固定上游地址；完整材料按 SHA-256 保存至共享磁盘缓存，失败重试复用已完成材料。校验错误直接停止，不默默换源。
- 新增依赖镜像元数据及维护者发布工具，仅上传原始源码/工具归档，不改写 13 个已认证构建输入。新增不可变对象遵循既有目录结构，不删除旧对象、不发布 DMG。

兼容与回滚：不改变运行时 ABI、版本、激活链路或任何用户容器；Wine 复用旧源码缓存路径。旧版仍可使用原有镜像和上游源；回滚构建适配即可恢复原流程。源码缓存可由系统回收，不影响已安装运行时。

验证：新增隔离缓存/并发/重试/回退/失败保留/取消/配方一致性测试及发布工具测试。`NefinitaBuildMaterialsTests`、`NefinitaWineSourceCacheTests`、`NefinitaSourceServiceTests` 共 14 项通过；`python3 -m unittest discover -s script/tests -p 'test_nefinita*publication.py'` 共 16 项通过；`./script/pr_preflight.sh` 无签名 Debug build 与资源边界检查通过。不在验证中执行真实 Wine 构建、容器初始化或游戏启动；完整本机编译与界面仍需手工验收。

发布影响：经用户授权新增 22 份不可变依赖/补丁归档，共 65,496,556 字节；逐项完成鉴权下载及匿名 HTTPS 内容校验。Wine 沿用已有镜像。无远端删除、App Release、DMG 上传或 Applications 替换。

# 迁移检查内存占用紧急修复

- 移除旧容器预检、复制后和切换前的文件内容哈希/回读校验；目录清单只读取路径、类型、大小、文件标识和修改时间，不加载游戏文件内容。
- 系统文件复制与目录遍历按条目释放临时对象，避免大型容器迁移时临时内存累积。
- 保留空闲状态、磁盘空间、符号链接边界、源目录变化检测、事务日志与中断恢复。相同大小不再被当作文件内容相同；不同源的同名应用文件保守报冲突，避免静默丢失存档。
- 同步移除升级流程中“校验成功”的表述。
- 兼容 2.0 的迁移日志格式；未完成事务沿用原恢复流程，已完成迁移无需重复执行。Runtime 1.1.2 不变。
- 验证：`./script/pr_preflight.sh` 无签名 Debug build 通过；`xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -only-testing:ArclumeTests/UnifiedContainerMigrationTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= SWIFT_EMIT_LOC_STRINGS=NO` 的 18 项隔离迁移测试全部通过。测试签名仅使用命令行 ad-hoc 覆盖，不改项目证书。
- 直接编译生产迁移服务，以 2 GiB 稀疏临时文件执行检查、迁移、收尾：通过，检查约 0.004 秒，进程峰值 RSS 11,255,808 字节；这是本机 APFS 合成用例，不等同于反馈用户的完整游戏库现场。
- 发布工作流制作 with-runtime/no-runtime DMG；不对开发机真实容器执行迁移。
- 手工回归：从旧版进入升级页，确认检查无需扫描游戏文件内容；退出 Windows 应用后迁移并启动已安装应用。反馈用户的原始崩溃报告尚未取得，不宣称已排除所有闪退原因。

回滚面：代码可退回前一版本，未完成迁移可按事务恢复；完成清理后的旧容器不再保留重复副本。移除内容校验后依赖系统复制错误反馈，不提供逐字节完整性验证。

# 自动合并旧容器中的内置系统文件

- 修复旧版 Steam / Games 容器中 15 项可自动处理的系统文件差异阻止升级的问题：`cxbottle.conf` 及两种 Program Files 目录下的 ADO、OLE DB、IE、Windows Media Player、写字板内置文件保留基础容器版本，不再进入阻塞冲突列表。
- 规则仅匹配明确的普通文件路径，不忽略整个 Program Files 目录，不放行同名链接、游戏文件、存档或旁边的用户配置。
- 不恢复文件内容扫描或哈希校验；沿用 2.0.1 的低内存目录检查与系统复制、事务日志和恢复机制，日志格式不变。
- 回归覆盖报告中的全部 15 项：合并、完成升级、保留基础组件和新增游戏存档；另验证相似路径及符号链接仍受保护。
- 回归发现并修正目录枚举在符号链接上调用 `skipDescendants` 可能跳过后续真实目录的问题。保持系统枚举器默认不跟随链接，补测根目录链接不会隐藏游戏目录，外部数据不被遍历或清理。
- 手工验证：遇到此报告的旧容器重新检查后应进入可开始迁移状态，不再停在仅可保存诊断报告的页面。未在真实用户容器上执行迁移。
- 验证结果：`./script/pr_preflight.sh` 无签名 Debug build 通过；`xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -only-testing:ArclumeTests/UnifiedContainerMigrationTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= SWIFT_EMIT_LOC_STRINGS=NO` 的 21 项测试全部通过，`git diff --check` 通过。未运行 UI XCTest。
- 回滚：迁移事务切换前后仍支持原恢复流程；完成清理后不保留重复旧容器。
- 发布：用户确认发布为 2.0.2（构建 12），Runtime 1.1.2 不变，生成 with-runtime / no-runtime 两种 DMG；不替换开发机已安装 App，不执行真实用户容器迁移。

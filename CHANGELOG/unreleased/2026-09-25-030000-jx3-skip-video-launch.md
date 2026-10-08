# 剑网3启动前补齐显卡评分配置

- 在统一的剑网3启动入口、创建游戏进程前确认 `config.ini` 的 `[Debug] SkipVideoCardScoreUpdate=1`，不再仅依赖初始化或画质导入。
- 使用原有 INI 定点更新逻辑，保留其他字段与换行风格；已为 1 时不重写，缺文件时不生成不完整配置，交由现有初始化轮询等待。
- 不区分 Arclume/Nefinita 运行时，不改变容器路径或 Wine 参数；写入异常记入日志，不覆盖整个配置或阻断启动。
- 回滚 App 可恢复原启动逻辑，已写入的单个配置键保留。手工验证：缺失该键或值为 0 时启动剑三，再检查配置及正常进入游戏。未自动启动用户游戏或修改真实配置。
- 验证：`xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -derivedDataPath /tmp/arclume-nefinita-derived -onlyUsePackageVersionsFromResolvedFile -only-testing:ArclumeTests/OnlineGameTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` 34 项通过（新增 4 项）；`./script/pr_preflight.sh`、`git diff --check` 与本地 Debug 构建通过。未覆盖 Applications、未提交或发布。

# 重写 Arclume 测试入口与隔离宿主

- 删除 Procyon 时期空断言 example、未隔离启动性能测量和截图启动模板；UI XCTest 改为 Arclume 模式选择、游戏库控件、未安装游戏 Steam 按钮、D3DMetal 选择器断言。保留有实质断言的核心/迁移测试，旧产品名作为迁移输入时不能删除。
- 增加共享 Scheme 与独立 Core/UI Test Plan；默认 Core，不默认运行 UI 自动化。
- Debug 测试宿主使用独立 UUID 偏好域，跳过真实迁移；核心测试空宿主不加载游戏库，UI fixture 禁用更新检查/扫描，使用无远程图片的固定库数据。移除 fixture 之前创建用户目录的副作用。
- Release 不响应测试环境变量，不改变正式安装用户的偏好和迁移流程。UI 测试不点击安装、游戏启动或清理按钮；实际 GUI runner 仍需单独授权和验收。

## 验证

- `xcodebuild test -testPlan ArclumeCore` 定向选择 ArclumeTests、GameAssociatedDataTests、LibraryLifecycleTests、WindowsGameLaunchRulesTests：19 项通过。
- `xcodebuild build-for-testing -testPlan ArclumeUI`：编译通过。
- 显式 `xcodebuild test -testPlan ArclumeUI -parallel-testing-enabled NO`：Runner 初始化失败，系统报告“已取消认证 / System authentication is running”；用例未执行，不计为通过，未自动授权。
- `./script/pr_preflight.sh`：无签名 Debug 与 Runtime 校验通过；`git diff --check` 通过。未运行旧的全量测试集合。

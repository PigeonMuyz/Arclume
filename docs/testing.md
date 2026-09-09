# 测试策略与 XCTest 计划

## 现状

`ArclumeTests/` 覆盖解析、迁移、Bottle、Runtime 验证、Steam 发现、适配规则和安全清理，主要使用 Swift Testing。`ArclumeUITests/` 使用 XCTest / XCUITest，依赖 macOS 桌面自动化和 App 激活。旧截图启动模板已移除。

共享 `Arclume` Scheme 默认选择 `ArclumeCore.xctestplan`，不会同时拉起 UI 测试。`ArclumeUI.xctestplan` 需要显式选择；桌面 Runner/授权失败先归类为环境问题。

## 当前入口（2026-09-09）

```bash
# 核心测试；日常仍建议加 -only-testing 选择本次影响的类
xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS'

# 只编译 UI 测试，不启动桌面自动化
xcodebuild build-for-testing -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeUI -destination 'platform=macOS'

# 显式选择的 UI 验证，需桌面 Runner 权限
xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeUI -destination 'platform=macOS'
```

- 核心测试宿主不加载真实 ContentView，不执行启动迁移；偏好使用独立 UUID suite。测试临时文件继续由各 fixture 清理。
- UI 用例统一设置 `ARCLUME_UI_TEST_FIXTURE=1` 和 UUID `ARCLUME_TEST_RUN_ID`；每次测试后退出 App 并清理该 UUID 偏好域。环境变量仅在 Debug 生效。
- 模式页和图形设置复用生产视图；库场景使用无远程图片的固定数据及拒绝安装的 Steam stub。关闭更新检查、真实库扫描和启动时用户目录创建。
- 已替换空 example、截图启动模板和未隔离性能测试。现有带 Procyon 迁移输入的核心测试应保留。
- UI 用例不点击游戏启动、安装、Wine 终止或真实清理按钮；有损行为只允许另外明确选择的隔离 fixture 验证。

## 目标分层

| 层级 | 范围 | 运行位置 | PR 默认状态 |
| --- | --- | --- | --- |
| B0：静态与构建 | 差异、Manifest、LFS、Debug build | 本地与 CI | 必须 |
| T1：核心测试 | `ArclumeCore.xctestplan` | 本地；CI 尚待接入 | 按影响范围选择 |
| T2：UI XCTest | `ArclumeUITests` + fixture | 有交互桌面会话 | 显式选择 |
| T3：Runtime / 游戏 | Wine、Games、SeasunGame、JX3ClientX64 | 真机手工验证 | 按影响范围 |

默认 PR workflow 仍只执行 B0；新 Test Plan 不改变 CI 发布或自动运行范围。

## 后续计划

### Phase 1：扩大核心隔离审计（入口已实现）

1. 已提供独立 Core/UI Plan，持续检查后续测试是否遵守隔离边界。
2. 核心 Plan 不包含 UI 目标；使用独立 `derivedDataPath`、测试环境和临时目录。
3. 为 `ArclumeTests` 补充测试前后清理规则，确认不读取真实 App Support、Steam、Bottle 或游戏目录。
4. 在本机用最小命令验证：

   ```bash
   xcodebuild test \
     -project Arclume.xcodeproj \
     -scheme Arclume \
     -only-testing:ArclumeTests
   ```

### Phase 2：建立 UI XCTest 基线

1. 已替换无断言模板；将来增加性能测试时继续与功能 PR 分离。
2. 所有 UI 测试必须显式设定 `ARCLUME_UI_TEST_FIXTURE=1`，不得访问真实用户数据。
3. 使用固定窗口尺寸、稳定 accessibility identifier 和截图/附件产物。
4. 将 UI XCTest 放入独立的手动 workflow 或夜间 workflow；只有在已验证的 GUI Runner 上才考虑 PR 门槛。

### Phase 3：Runtime 合同测试

1. 使用小型测试归档验证 Manifest、ABI、SHA-256、原子替换和旧 Runtime 回滚。
2. 迁移测试必须验证 `Games` 容器不被复制、覆盖或删除。
3. 不在 CI 下载 Wine、初始化真实 Games 前缀或启动 SeasunGame/JX3ClientX64。
4. 真机游戏验证保留在 PR 的手工验证记录中。

## PR 验证矩阵

| 改动 | B0 | T1 | T2 | T3 |
| --- | --- | --- | --- | --- |
| 文档 / 模板 | 是 | 否 | 否 | 否 |
| 纯服务 / 解析 / 迁移 | 是 | 对应测试 | 否 | 视影响 |
| SwiftUI 交互 | 是 | 相关逻辑 | 显式运行 | 否 |
| Runtime / Manifest | 是 | 合同测试完成后 | 否 | 必须说明 |
| 启动器 / 剑网 3 | 是 | 进程与配置测试 | 视 UI | 手工真机 |

## 失败分流

- **编译失败**：先修构建，再讨论测试。
- **断言失败**：记录最小失败用例、输入和预期。
- **崩溃 / signal**：保留崩溃报告和测试日志，区分测试宿主与 App 进程。
- **Runner / 授权失败**：标为环境问题，先用 T1 或受控 GUI Runner 重现。
- **异步 / 时序问题**：禁止无限重试；应增加明确等待条件、隔离 fixture 或最小复现。

## 当前约束

在该计划完成并经维护者批准前，任何 Agent 或 CI 都不得把全量 `xcodebuild test` 当作默认检查。每次需要运行测试时，应选择最小目标并在 PR 中报告命令、范围、结果与未覆盖部分。

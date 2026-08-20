# 测试策略与 XCTest 计划

## 现状

`ArclumeTests/` 已覆盖解析、迁移、Bottle、Runtime 验证、Steam 发现和进程监控等核心逻辑，主要使用 Swift Testing。`ArclumeUITests/` 与 `ArclumeUITestsLaunchTests.swift` 使用 XCTest / XCUITest，依赖 macOS 桌面自动化和 App 激活。

因此，笼统执行 `xcodebuild test` 会同时拉起 UI 测试；在无交互授权、远程桌面或 CI 环境中，它可能因测试 Runner 初始化而失败。这类失败首先应归类为环境/授权问题，不应直接归因于产品逻辑。

## 目标分层

| 层级 | 范围 | 运行位置 | PR 默认状态 |
| --- | --- | --- | --- |
| B0：静态与构建 | 差异、Manifest、LFS、Debug build | 本地与 CI | 必须 |
| T1：核心测试 | `ArclumeTests` | 本地与 CI | 规划为必须 |
| T2：UI XCTest | `ArclumeUITests` + fixture | 有交互桌面会话 | 显式选择 |
| T3：Runtime / 游戏 | Wine、Games、SeasunGame、JX3ClientX64 | 真机手工验证 | 按影响范围 |

当前只执行 B0。T1 和 T2 在新 Test Plan 完成前不自动接入 PR workflow。

## 新 Test Plan 的实施计划

### Phase 1：隔离核心测试

1. 新建共享 `Arclume.xctestplan`，将 `ArclumeTests` 命名为 **Core Tests**。
2. 在该 Plan 中禁用 `ArclumeUITests`，并使用独立 `derivedDataPath`、测试环境和临时目录。
3. 为 `ArclumeTests` 补充测试前后清理规则，确认不读取真实 App Support、Steam、Bottle 或游戏目录。
4. 在本机用最小命令验证：

   ```bash
   xcodebuild test \
     -project Arclume.xcodeproj \
     -scheme Arclume \
     -only-testing:ArclumeTests
   ```

### Phase 2：建立 UI XCTest 基线

1. 删除 `testExample()` 这类无断言测试，并将启动性能测试从功能 PR 中分离。
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

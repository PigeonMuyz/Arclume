# PR 前置审核规范

PR 审核分为作者自检、自动预检和维护者审核。任何一层发现范围不明、验证不足或用户数据风险时，都应退回补充，而不是用“看起来可行”放行。

## 作者自检

提交 PR 前必须：

1. 阅读受影响代码与直接调用方。
2. 新增 `CHANGELOG/unreleased/` 记录。
3. 执行 `./script/pr_preflight.sh`。
4. 填写 PR 模板中的验证证据、风险和 AI 辅助声明。
5. 不把个人日志、Bottle、游戏资源、LFS 临时文件或凭据纳入 PR。

## 自动预检（B0）

`pr-preflight.yml` 只做无交互、可复现的检查：

- Git 差异空白错误；
- Runtime Manifest 格式、归档名和 SHA-256；
- 只读 Git LFS 状态（不会为审核而移动本地对象）；
- 无签名 Debug build；
- 发布 workflow 的 YAML 可解析性。

它不会运行 XCTest、下载游戏、初始化真实 Wine 前缀或启动游戏。核心测试 CI 将在 [测试策略](testing.md) 的 Phase 1 完成后单独加入。

## 维护者审核清单

### 通用

- PR 是否只解决一个逻辑问题？
- 变更记录、文档和验证证据是否齐全？
- 是否有无关格式化、秘密、个人路径或二进制污染？
- AI 辅助部分是否经过人工复核？

### 用户数据、迁移与启动

- 是否触碰 `Games`、Bottle、偏好或日志保留策略？
- 失败与取消能否保留旧状态？
- 是否有最小可复现的迁移/启动验证？

### Runtime 与资源

- Manifest、ABI、架构、根目录、归档名和 SHA-256 是否一致？
- 是否避免复制、覆盖或删除用户 Prefix？
- 是否同步更新 Runtime 项目的对应变更与版本说明？

### 发布与更新

- `MARKETING_VERSION`、构建号、Release 指令和变更记录是否一致？
- 是否正确区分 `with-runtime` 与 `no-runtime`？
- 是否避免在普通 PR 触发 Release？

## 门禁限制

当前私有仓库无法使用传统 GitHub branch protection API，因此 Actions 状态是可见审核证据，而非平台强制门禁。需要硬性禁止未通过检查的合并前，维护者必须调整 GitHub 仓库方案或确认可用的 Ruleset，并将该决定记录到变更记录中。

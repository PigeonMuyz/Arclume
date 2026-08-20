# Arclume Wine Runtime 合同

## 两个项目的边界

| 项目 | 负责内容 |
| --- | --- |
| Arclume App | 设置、Bottle、启动器、Games 容器、更新 UI、Runtime 安装器和 Manifest 消费。 |
| Arclume-Runtime | Wine 源码锁定、补丁、构建、归档、Runtime ABI 和 Release Manifest。 |

App 不应在本仓库内重编 Wine，也不应根据目录猜测 Runtime 版本。

## Manifest 是唯一合同

`Arclume/Resources/OnlineGameDependencies/arclume-wine-runtime.json` 固定：

- Runtime ID、显示名、版本和发布通道；
- `runtimeABI`、`prefixABI` 与架构；
- 最低 macOS 版本；
- 归档文件名、根目录和 SHA-256；
- 旧安装根目录和迁移标识。

只有当 ID、Runtime ABI、Prefix ABI 和架构兼容时，App 才能原地替换 Runtime。任何 ABI 变更都可能要求新的 Games 前缀迁移策略，不能把它伪装成普通 Runtime 更新。

## 用户数据边界

- Runtime 是可替换的不可变文件，位于 `OnlineGameRuntimes/`。
- `Games` Bottle / Prefix 位于独立路径，是用户状态。
- Runtime 更新只允许原子替换 Runtime；失败时必须恢复旧 Runtime。
- 不得因更新复制、移动、删除或重建 Games 前缀。

## 接入新的 Runtime Release

1. 在 Runtime 项目完成构建、测试、归档和 SHA-256 校验。
2. 审核 Manifest 的 ABI、迁移和最低系统版本。
3. 使用 `script/embed_runtime_release.sh` 接入 App，保留可审查的 Manifest 和 LFS 差异。
4. 运行 App 的 Runtime 合同验证与受影响游戏的手工启动验证。
5. 记录变更到 `CHANGELOG/unreleased/`，并在发布前同步 [发布文档](release.md)。

## 镜像与私有发布

App 更新源使用 GitHub Release API 与资产 URL。若 Release 保持私有，普通用户客户端不能携带维护者凭据；自定义镜像必须能安全地代理或重新托管 Release 元数据和资产，而不仅是下载加速地址。无论来源如何，App 都必须验证 Manifest 与 SHA-256。

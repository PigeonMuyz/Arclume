## 摘要

<!-- 用两三句话说明用户可见结果和实现边界。 -->

## 影响范围

- [ ] App / SwiftUI
- [ ] 游戏发现、启动或进程管理
- [ ] CrossOver 集成
- [ ] Arclume Wine Runtime / Manifest / Prefix
- [ ] 更新、发布或镜像源
- [ ] 文档、构建或治理

## 变更留痕

- [ ] 已新增 `CHANGELOG/unreleased/YYYY-MM-DD-HHMMSS-<slug>.md`，未改写历史条目。
- [ ] Runtime 有变更时，已同步核对 Manifest、ABI、归档 SHA-256 与迁移边界。
- [ ] 用户数据、`Games` 容器、Bottle 和本地配置不会被意外删除、复制或覆盖。

## 验证

- [ ] 已运行 `./script/pr_preflight.sh`（静态检查与 Debug build；不会运行 XCTest）。
- [ ] 已说明未覆盖部分及原因。
- [ ] 如涉及界面，已在 macOS 上手工检查主要状态。
- [ ] 如涉及 Runtime 或剑网 3，已附上脱敏后的手工验证说明。

验证命令与结果：

```text
请填写。
```

## 发布与兼容性

<!-- 如不适用，填写“无”。包括最低 macOS、已有用户迁移、Runtime 兼容性和 Release 影响。 -->

## AI 协助披露

<!-- 如使用 AI，请说明它协助了什么，以及你如何完成了人工审核和验证。 -->

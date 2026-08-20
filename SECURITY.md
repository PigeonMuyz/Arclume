# 安全策略

## 支持范围

安全修复优先覆盖 `main` 和最新公开 Release。预发布功能、实验性 Runtime 与第三方游戏本体不保证长期兼容，但我们仍欢迎负责任的报告。

## 报告漏洞

请不要通过公开 Issue、讨论区、日志附件或截图披露漏洞细节。优先使用 GitHub Private Security Advisory：

<https://github.com/PigeonMuyz/Arclume/security/advisories/new>

报告应包含最小复现步骤、受影响版本、预期与实际结果、影响评估，以及可选的修复建议。不要上传用户的 Steam 凭据、游戏账户信息、完整 Bottle、个人目录快照或未脱敏日志。

## 响应原则

维护者会确认接收、评估影响、安排修复，并在修复发布后给予致谢（除非报告者要求匿名）。修复公开时间会以用户安全和可复现性为准。

## 不属于本仓库的范围

- CrossOver、Wine、DXVK、D3DMetal、Steam 和游戏客户端自身的上游漏洞；
- 需要用户提供密码、令牌或绕过平台安全机制的报告；
- 已公开且没有 Arclume 特定影响的第三方问题。

如果第三方问题会通过 Arclume 的启动、更新或 Runtime 安装路径造成额外风险，请仍通过上述渠道报告。

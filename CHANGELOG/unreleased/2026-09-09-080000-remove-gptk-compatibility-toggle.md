# 移除游戏兼容性中的 GPTK 4 Beta 2 覆盖开关

- 时间：2026-09-09T08:00:00+08:00
- 类型：fix
- 范围：App 游戏设置与启动

## 改动

- 移除游戏兼容性编辑器的 GPTK 4 Beta 2 勾选项，以及从详情/游戏库启动时对图形后端的隐式覆盖。
- 历史 Steam 与自定义游戏兼容性 JSON 中的 gptk4BetaEnabled 字段按未知字段忽略，保留兼容状态和系统要求。
- 不删除 D3DMetal 运行时资源，不调整全局后端选择，不重置游戏数据与画质。

## 兼容性与回滚

- 旧配置仍可解码；新保存的兼容性资料不再包含已移除字段。撤销本次代码即可恢复开关，重新保存过的条目需重新选择旧开关。
- 本次本机修复仅将终末地性能 HUD 恢复为关闭，与先前成功启动的配置一致；不推广为所有游戏的默认规则。

## 验证

- 更新隔离 UserDefaults 测试，覆盖 Steam 与自定义游戏历史勾选项的兼容解码。
- `./script/pr_preflight.sh`：无签名 Debug build、Manifest/归档校验与工作流检查通过。
- 定向运行 GameCompatibilityStoreTests 与 WindowsGameLaunchRulesTests：16 项通过，未运行 UI XCTest。
- `./script/build_and_run.sh --verify`：开发版启动通过；真实详情界面已无 GPTK 勾选项，并通过“游玩”按钮启动 Endfield.exe，窗口参数与 HUD 关闭状态已核验。
- 不覆盖安装版；游戏主画面恢复情况以用户的本次运行反馈为准。

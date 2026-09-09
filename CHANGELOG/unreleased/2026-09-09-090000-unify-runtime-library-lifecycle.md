# 统一内置 Wine、游戏资料与移除流程

- 时间：2026-09-09T09:00:00+08:00
- 类型：feature
- 范围：App 运行时、游戏库、元数据、卸载

## 改动

- 撤下 CrossOver 运行时入口，应用启动时选择内置 Wine，旧容器路径单独保留；旧关联入口要求重新配置，不复制、删除或自动迁移 CrossOver 文件。
- 内置图形选项收敛为 D3DMetal 3 / 4，按设备能力显示；说明 Vulkan 游戏不由该选项决定 API。取回仓库原有 D3DMetal 3 LFS 归档，不修改发布清单或归档版本。
- 接入 LizardByte GameDB 公共静态 API（资料来源 IGDB），提供名称搜索、预览确认关联、缓存资料与七日刷新。已验证终末地身份自动关联 194558；手工字段优先，只补空白。
- Windows 自定义游戏也可关联已有 Steam 元数据服务。GameDB 不改变游戏名、EXE、容器和启动参数；断网保留旧资料。
- 区分隐藏与卸载：隐藏保存忽略记录防止扫描回添，设置可恢复扫描；卸载仅对确认独立目录的终末地开放，预览大小与路径、用户确认后移至废纸篓，存档和登录资料默认保留。
- 游戏移除后，确认没有其他关联内容时另行询问移除鹰角启动器。进程、路径、链接、共享内容检查失败时拒绝删除；其他程序请通过原启动器卸载。

## 兼容性与回滚

- 本轮不删除实际游戏、不改 Runtime ABI、不发布或替换安装版。保留旧 CrossOver 底层解码与适配代码便于后续清理/回滚。
- 回滚需恢复旧运行时选择与保留的容器路径；元数据关联和隐藏记录独立保存。废纸篓清空前可手工恢复安装目录。
- GameDB 地址：https://github.com/LizardByte/GameDB 。仅通过公开接口读取数据，未复制 Sunshine/GameDB 源码；图片来源 IGDB。

## 验证

- 新增隔离测试覆盖旧运行时偏好保留、元数据手工覆盖、图片来源限制、卸载路径和共享启动器规则。
- `xcodebuild test` 定向运行 LibraryLifecycleTests、WindowsGameLaunchRulesTests、GameCompatibilityStoreTests，20 项通过；`./script/pr_preflight.sh` 无签名 Debug build 与 Runtime 校验通过。
- `./script/build_and_run.sh --verify` 通过并启动开发版；真实界面已确认终末地封面、简介、开发商、类型与截图资料接入。
- UI 工具在继续检查设置时断连，应用进程仍在运行；完整菜单交互和 D3DMetal 3 实际游戏画面尚未验收。
- 未对用户真实目录执行卸载；不运行 UI XCTest，不覆盖 `/Applications/Arclume.app`。

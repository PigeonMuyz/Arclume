# 容器管理（第一阶段）

## 当前范围

- 设置 → 容器：列出默认 ALBottles 和用户创建的容器；支持新建、重命名、单独初始化及打开目录。
- 新建时选择 Arclume Runtime 或 Nefinita。创建仅保存记录；点击初始化才运行 Wine，运行时与图形组件须先准备好。
- 游戏 → 运行设置：展示已有容器归属，选择器暂时禁用。服务层同样拒绝分配；不修改启动路径，不搬移游戏。
- 不包含 CrossOver ARM64 Wine：没有提取、内嵌或上传 CrossOver 文件。

## 数据与兼容性

列表以 `managed-wine-containers.v1` 保存于 Arclume 偏好域，带 schemaVersion。自定义容器路径为 App Support 下的 `Containers/<UUID>`；显示名不参与文件路径或 staging 名称。

默认记录不写入目录列表，继续指向原 ALBottles，并显示现有全局运行时选择。新容器绑定的运行时不会改变此全局偏好。旧版忽略新列表，因此仍可使用原默认容器。

初始化不接受默认容器、未登记 ID 或经过符号链接的管理路径。既有无效目录不会被清理或覆盖。新建初始化在随机 staging 中完成后才发布；wineboot 等待 120 秒，超时尝试按本次 staging 前缀停止 wineserver，并保留 staging，避免清理仍在退出的进程。失败不会触碰其他容器。

初始化复用引擎的 D3DMetal 模块准备流程，可能补全共享运行时模块；它不是游戏迁移。目前不提供删除、跨容器启动和自动迁移入口。

## 验证

- `./script/pr_preflight.sh`：无签名 Debug build、资源打包边界与静态审核。
- 选择 `ManagedWineContainerTests`、`RosettaStatusServiceTests`、`NefinitaRuntimeTests` 执行隔离核心测试。测试仅使用临时目录、独立偏好域和测试自建的短生命周期命令，不启动 Wine、游戏或真实容器。
- `python3 -m unittest discover -s script/tests`：资源上传、版本保留与构建材料发布的本地测试，不上传对象。

手工验收请使用测试账户：准备运行时、创建容器、初始化、重命名及打开目录；重启检查列表保留，确认默认游戏启动路径未变，游戏容器选择器不可操作。真实 Wine 初始化、GUI 视觉效果与游戏运行不能由核心测试结果替代。

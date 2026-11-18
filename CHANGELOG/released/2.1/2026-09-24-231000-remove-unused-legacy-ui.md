# 清理废弃页面和旧品牌展示残留

- 时间：2026-09-24T23:10:00+08:00
- 类型：fix
- 范围：App

## 改动

- 移除无调用的 CustomGameView、NativeAppLaunchSettingsView、GameCompatibilityEditor、GameLibrariesList 和 VPlayerLayerView；当前编辑入口仍使用 ProjectEditorView 和 NativeProjectOptionsView。
- 移除仅由旧页面调用的 CustomGameAPI / GameResponse，以及无调用的重复 SteamGameResponseArray、旧自动填充开关和 LIB_ROOT 常量。
- 移除没有代码加载入口的旧 Procyon Lottie 动画资源；清理生成文件头、普通注释和提示中的旧品牌名称，保留原作者署名。

## 用户影响与兼容性

- 不移除现有页面入口、资料匹配、运行设置、兼容性模型或存储服务。
- 保留旧版迁移目录、偏好键、运行时协议和环境变量标识、旧缓存和备份后缀，以及相应测试输入；不修改 Runtime Manifest、归档或用户数据。
- 本次产物为本地验证 DMG，不触发 GitHub 发布或对象存储上传。
- 回滚只需恢复被删除的源码和未使用资源，无用户数据迁移。

## 验证

- 删除前已核对生产代码、测试和动态入口；Debug 预检与 Release archive 构建通过，迁移/本地化/元数据/下载等 17 组定向核心测试共 95 项通过，脚本测试 21 项通过。
- 本地 DMG 使用临时签名而非 Developer ID，不代表公证或游戏启动验收；未执行 UI XCTest。

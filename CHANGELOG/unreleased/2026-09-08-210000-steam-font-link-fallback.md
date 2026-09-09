# 修复 Steam 更新窗口中文方框

- 实测发现 Wine 优先使用已存在的 Tahoma/Arial，FontSubstitutes 无法强制替换；对这些字体设置替换还会使 Wine 跳过其 SystemLink。
- 改为给常见界面字体添加 Noto CJK SystemLink，保留英文原字体。仅移除上一版写入的同名 Noto 替换值，不清理用户的其他替换。
- 在导入前通过 reg.exe 导出实时字体配置，保留已有后备字体列表；重复准备不会叠加 Noto 条目。异常列表停止处理，不直接覆盖。
- 仍在安装和打开 Steam 前异步准备，兼容 32/64 位注册表；不改 Runtime 归档、输入法、图形设置，不重建容器或安装 Steam。

## 验证

- 使用同一 Swift 配置生成代码检查已有列表保留、重复执行幂等和旧规则定向移除。
- 本机现有 Steam 容器中的 32/64 位 GDI 绘字探针验证：Noto、Tahoma、Arial、MS Shell Dlg、MS Sans Serif、SimSun 正常绘制中文。探针不启动 Steam、不登录账户；实际 Steam 更新窗口仍需用户复测。
- 执行 Debug build 和 pr_preflight；不运行 XCTest。

## 用户数据与回滚

- 修复仅更新目标 Steam 容器字体文件及相关注册表项；诊断时已将修正规则应用到本机 Steam 容器。游戏、Steam 安装和账户数据不变。
- 旧 App 会重新写入有问题的替换项，因此不应仅回退 App 后继续反复打开 Steam。

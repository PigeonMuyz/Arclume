# Steam 容器中文显示修补

- 在安装 Steam 前和应用内打开 Steam 前，异步安装/核对内置 Noto Sans CJK SC 字体，并通过当前容器的 Wine reg.exe 导入 32/64 位注册表视图。
- 补齐 Tahoma、MS Sans Serif、Microsoft Sans Serif、Segoe UI、Arial 等界面字体及中文字体别名，设置简体中文区域/代码页；只作用于所选普通容器，不套用剑三键盘、调试或图形配置。
- 已有 Steam 无需重装；字体文件内容一致时不重复替换，不直接编辑正在使用的 system.reg / user.reg。准备阶段禁用重复打开，导入失败或超时显示错误。
- 独立临时目录检查：字体中文字符覆盖、UTF-16 注册表文件、别名映射、文件幂等写入及原注册表不变；Debug build / PR preflight，不运行 XCTest。
- 尚需实测 Steam 更新窗口渲染；本次未运行或终止用户 Steam、未覆盖已安装应用。已运行的 Steam 需要退出后重新打开，才能重新加载字体。

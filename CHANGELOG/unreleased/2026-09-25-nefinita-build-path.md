# 修复 Nefinita 在带空格目录下构建失败

- 实际日志确认 FreeType 的 configure/Makefile 将 `Application Support` 拆分为两个路径；配方与 Wine 源码下载已成功。
- 构建工作区改为无空格的物理缓存路径，必要时使用系统临时目录；拒绝 Make/shell 路径分隔符及指向不兼容物理路径的符号链接。新会话使用独立 UUID 和 0700 权限。
- 构建日志仍保留在原 App Support 位置，并记录工作区位置。不移动、复制或删除旧会话、现有运行时及 ALBottles，不修改上游脚本或固定配方校验值。
- 新增隔离路径测试，与运行时测试共 13 项通过；无签名 Debug 预检通过。同一固定 FreeType 2.13.3 归档在无空格隔离目录实际配置和编译通过，产物为 x86_64 Mach-O dylib。完整 Wine 编译与游戏兼容性仍需单独验收，不以 App 构建通过代替。

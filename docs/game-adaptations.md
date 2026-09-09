# Windows 游戏适配规则

规则位于 `Arclume/Resources/GameAdaptations/`，每个厂商一个 JSON，`schemaVersion` 当前为 1。同文件包含启动器和所属游戏；文件夹作为完整资源打包，新增文件不必修改 Swift 或 Xcode 文件列表。对应结构约束见 `docs/game-adaptations.schema.json`，运行时还会校验路径、ID 与关联关系。

## 主程序图标与进程名称

Windows 卡片没有封面或封面加载失败时，从主 EXE 的 PE 资源中读取 RT_GROUP_ICON / RT_ICON，居中显示实际程序图标；快捷方式先解析目标。不会运行 EXE 或调用 BAT，没有图标才保留通用占位图。解析限制文件 128 MiB、资源 8 MiB，内存缓存按路径、文件大小和修改时间区分。

文档顶层可增加 `processNames`：

```json
"processNames": [
  {"executable": "YY.exe", "name": "YY语音", "ruleID": "yyspeak-portable"}
]
```

只匹配完整 EXE 文件名（不区分大小写），不做 `YY*` / `wine*` 通配。`ruleID` 引用同文件安装规则并复核目录和必要文件；旧剑网3仅展示规则使用 `ancestorDirectoryName` 约束，不额外限制或迁移其安装目录。仅展示文档允许 `rules: []`。同时匹配多个展示规则时不改名。

公共环境清除旧 `PROCYON_WINE_DOCK_NAME` 和 `WINEPRELOADERAPPNAME`，只为精确匹配的当前启动 EXE 设置一次 `WINEPRELOADERAPPNAME`；Wine loader 消费并清除它，子进程由 Wine 按各自 EXE 命名。不会给未知程序继承剑网3名称，不使用全局 Dock 覆盖。JSON 不拦截第三方启动器自行创建的 Windows 子进程，因此对子进程的中文别名不作保证。已有进程须正常退出后重新启动才能看到新名称。

`captureErrors: true` 可针对已匹配的直接启动入口记录 Wine stderr，当前用于 YY 登录后立即退出排查。日志位于 `Application Support/Arclume/WindowsProgramLogs/<UUID>.log`，权限 0600，每次最多 4 MiB，达到上限继续排空管道但不再保存。不会主动导出注册表、账号数据库或输入；错误输出仍可能含私人路径/程序信息，对外分享前应脱敏。日志不自动上传或删除，排障后可关闭该规则字段。YY 现有二进制 `.lg` 日志与音视频模块清理日志不足以确认崩溃根因，广告屏蔽和 `yyrun.exe -reg` 需分开验证，不能据此直接执行整个 BAT。

## 当前范围

- 卸载界面提供“仅卸载，保留游戏数据”和“移除全部”两档，路径/大小折叠显示。“全部”仅指所选程序及已识别的数据，不包括共享/未知数据或云端账号。
- 从启动器发起卸载时，发现关联游戏就警告可能影响启动或大版本更新，并提供默认关闭的“一并移除关联游戏”。同时检查磁盘和游戏库，不只依赖已添加入口。存在未识别游戏时禁用合并卸载，仍可只移除启动器。
- `launcherRemovalEntries` 指定启动器根目录下可移除的精确子项，禁止填写 `games`。`launcherVersionDirectories` 允许识别包含有效辅助 EXE 的数字版本目录。保留游戏时只移除这些启动器子项，绝不将整个启动器根目录移走；未知文件保留。

- `hypergryph.json`：鹰角启动器、明日方舟：终末地。身份通过 EXE 名、PE 文件头、必要文件（游戏）或启动器祖先目录确认。不是安全签名验证，也不证明安装包可信。
- 安装、自动添加、手工添加和启动共用目录规则。已有偏离目录的文件不移动、不删除；需用户在原启动器选择规定目录或重新安装后扫描。
- `installDirectory` 相对于选定 Arclume Wine 容器的 `drive_c`，不接受绝对路径、`..`、空路径段、盘符和反斜杠。不修改用户的 Wine 映射或文件系统权限。
- NSIS 安装包通过名称前缀、PE 头、NSIS 标识匹配。只传 `/D=` 默认目录，保留安装 UI 与许可确认，不用 `/S` 静默安装。NSIS 要求 `/D` 是不加引号的命令行尾部，因此 Wine 参数按空格拆分后组装。第三方安装器可以覆盖此默认值，Arclume 只能拒绝接入不合规路径，**不是文件系统级“锁死”**。
- 终末地游戏本体由鹰角启动器下载，不伪造游戏下载接口或改写未验证的启动器配置。下载时仍需在启动器内选用规则显示的路径。实际新装流程需人工验收。

## 字段

`id` 稳定不变；`name` 是展示名；`kind` 为 `launcher`、`game` 或绿色软件使用的 `application`。

`executable` 是主入口；`alternateExecutables` 用于版本化启动器辅助入口。`requiredFiles` 是相对 EXE 所在目录的完整安装标识。`ancestorDirectoryName` 可进一步限制启动器身份。

`launcherID` 关联同文件启动器；游戏目录须在其 `games/` 下。删除启动器前还检查是否有其他目录或关联入口，不根据 JSON 直接递归删除厂商目录。

`defaultArguments` 为参数组数组，如 `["-screen-width", "1280"]`；用户显式指定的同名参数优先。不会作为 Shell 脚本执行。`gameDBID` 需人工核验为本体条目而不是更新包。

`userDataDirectory` 相对于每个 Windows 用户目录。`dataEntries` 仅允许精确子项名，或者名字前缀加 `hexSuffixLength: 32`。分类为 `logs`、`local`、`login`，默认不勾选。未知内容与同级共享 SDK 目录保留，不把整个厂商目录当作缓存。

`registryKey` 使用 Wine `user.reg` 的双反斜杠表示（JSON 中每个双反斜杠写成四个反斜杠），只清理精确键及其子键，不清相似前缀。仅在所有 Wine/EXE 进程退出后离线修改；在 `Application Support/Arclume/RemovalRecovery/<UUID>/game-user.reg.fragment` 保存所选片段，目录权限 0700、文件 0600，不备份整个注册表。失败时报告已完成项，不声称批量操作具有事务性。

## 恢复与边界

文件通过废纸篓恢复。注册表片段**不是可双击导入的 Windows .reg 文件**：需退出所有 Wine 程序，确认当前 `user.reg` 没有同名键，再将片段手工合并；不要覆盖新设置。恢复片段可能含私人设置，不要提交仓库，确认不需要后可手工删除。

清理本地数据不等于删除云端账号/存档。共享登录 SDK 和 Arclume 自身启动选项仍保留。当前只提供卸载预览中的关联数据清理，游戏入口已移除后的“孤立残留扫描”未实现。

## 投稿与验证

1. 同一厂商规则一起提交，提供安装器来源、版本、默认路径、PE/标识文件证据和脱敏目录结构。
2. 新增隔离 fixture 测试：正确识别、错误目录拒绝、符号链接拒绝、共享数据保留、参数不覆盖用户输入。禁止使用个人容器作为测试 fixture。
3. 执行定向 `GameAssociatedDataTests`、`WindowsGameLaunchRulesTests`、`LibraryLifecycleTests` 与 `./script/pr_preflight.sh`。
4. 人工验证第三方安装器实际参数接收、安装目录、二次启动和卸载预览。真实删除测试须用户单独授权。

只读取随 App 分发并审核的 JSON，不远程下载执行规则，不接受 Shell/脚本或任意删除命令。

## 绿色软件压缩包与整包更新

“安装 Windows 程序”同时接受 ZIP、7z、RAR。先解压到独立临时目录，再预览主程序和固定目录，确认后导入；不会自动启动软件。未匹配规则时保留完整包内目录（仅剥离单一外层文件夹），由用户选择主 EXE，导入独立的 `PortableApps/Custom-UUID`。未知软件不根据同名 EXE 自动覆盖旧安装；整包自动更新需补充审核后的规则。

`yyspeak.json` 示例：根目录 `YY.exe` 与 `yylauncher.exe` 匹配 YY 绿色包，导入 `C:\PortableApps\YYSpeak`，工作目录为主 EXE 所在目录。版本化辅助 EXE 不作为主入口，不带入软件目录外的推广文件。来源是第三方修改包；PE/路径匹配仅用于识别，不代表官方签名验证或安全保证。没有验证 YY 登录、麦克风、语音通话兼容性，`yyrun.exe -reg` 的必要性仍待独立测试。

绿色规则使用 `kind: application`，附加：

```json
"portable": {
  "scriptPolicy": "skip",
  "preservePaths": []
}
```

- 固定目录必须为 `PortableApps/软件目录`，不得关联启动器或 NSIS 安装器。`requiredFiles` 不得为空；必须有实际版本目录证据，不能仅按压缩包文件名判断。
- `scriptPolicy` 目前只允许 `skip`：保留包内 BAT/CMD/PS1 文件，但 Arclume **绝不主动执行**。程序自身仍属于用户信任的软件，可以执行自己的逻辑；这不是沙箱。提权、taskkill、删旧配置、广告封堵、快捷方式生成等不作为通用安装步骤。
- `preservePaths` 是需要从旧安装迁入新版的精确顶层数据文件/目录名，无通配符、子路径和脚本命令。旧数据优先于包内同名初始数据。YY 目前没有已验证的安装内跨版本数据项，因此为空；整包替换本身不改 AppData 和注册表，下面的可选绿色适配单独处理限定的广告路径。安装内未知本地文件留在旧版恢复目录，不自动合并进新版。
- 再选新版压缩包，匹配相同规则、固定目录和 Arclume 导入收据后，按钮变为“替换更新”，二次确认再操作。非托管/不匹配的已有目录拒绝覆盖。库入口路径保持不变、不重复添加；不判断版本大小，因此也可由用户明确选择旧包降级。
- 替换前要求所有 Wine/EXE 程序退出；不自动杀进程。在目标同卷目录暂存新版，通过 macOS `RENAME_SWAP` 原子切换。失败不改动旧安装；成功后旧目录留在 `PortableApps/.arclume-recovery-UUID/previous`，窗口提供“打开旧版本恢复目录”。恢复副本可能包含个人设置，不上传、不自动清理。
- 手工回滚：先退出所有 Windows 程序，保留当前固定安装目录到其他位置，将恢复目录里的 `previous` 移回原固定安装路径；不能直接在恢复目录启动适配软件。未知个人文件可从恢复目录单独取回。恢复目录不参与库扫描；卸载当前软件也不会自动删除历史恢复副本。
- 已导入软件支持现有卸载预览。YY 关联数据只识别每个 Windows 用户的 `AppData/Roaming/duowan/yy`；不清整个 duowan 厂商目录、不调用包内卸载 BAT。

解压使用系统 libarchive 的只读流接口，逐项写入私有临时目录，不恢复归档权限、符号链接、硬链接或特殊文件。拒绝越界、盘符、Windows 保留名、重复/大小写冲突路径和伪造导入收据；限制 50,000 条目、8 GiB 实际解压数据。加密、分卷、损坏、编码无法解读或系统不支持的格式报错，不尝试外部解压命令或脚本。不同 macOS 的格式能力以实际解码结果为准。接口依据：[libarchive 官方读取示例](https://github.com/libarchive/libarchive/wiki/Examples)。

投稿须提供：下载来源、版本、脱敏包内结构、主 EXE 证据、脚本静态审查、用户数据路径，以及隔离导入/替换失败/保留数据测试。新增必要注册步骤必须经过代码审核，当前 JSON 不支持任意命令。定向测试：`PortableSoftwareTests`。

### BAT 去广告步骤的声明式适配

`scriptPolicy: skip` 只表示不运行原始脚本，不表示放弃去广告功能。审核后的绿色规则可添加：

```json
"greenPreparation": {
  "blockedDirectories": ["yy/mainframe/ad", "yy/cache/loginbanner"]
}
```

路径相对于该规则的 `userDataDirectory`，必须是精确的至少两级相对路径，最多 64 项；运行时拒绝越界、符号链接、特殊文件、大小写重复和父子路径重叠。只接受随 App 审核发布的规则，没有任意命令、通配符或远程脚本。

YY 9.58 的当前规则选取原 BAT 的 24 个广告、游戏推广和内置更新目录。应用时，先写恢复清单，将原目录移动到同容器 `drive_c/.arclume-green-recovery/<UUID>/original-N`，再建立带 Arclume 标记的只读空文件，阻止原路径作为目录接收下载。不会清空整个 duowan、账号设置或注册表，不禁止日志，不执行提权、批量 taskkill、`yyrun.exe -reg` 或其他尚未确认必要性的步骤。此列表是审核后的子集，不承诺覆盖未来版本所有广告。

导入或整包替换时可勾选“应用绿色适配”；已有 YY 右键“应用绿色适配…”可预览后执行。需要所有 Windows 程序退出。重复应用跳过自己的占位文件，整包替换不动 AppData 中已有屏蔽。绿色适配失败不会撤销已完成的软件导入，UI 分别报告结果和恢复位置。

适配窗口提供“打开恢复目录”和“撤销此次适配”，重新打开窗口仍能找到最近一次未撤销记录。撤销只移除带本规则标记、内容仍为空的占位文件，再移回原内容；如果文件已被用户或程序改写，拒绝覆盖并保留恢复目录。部分失败会报告已处理项，不声称批量事务成功。恢复记录可能含私人内容，不上传、不自动清除。

隔离测试：`PortableGreenPreparationTests` 覆盖屏蔽、账号/共享目录保留、重复应用、撤销、运行中拒绝、符号链接与中途失败。真实 YY 去广告效果、整包更新后的行为及登录即退出原因仍需手工验证，不以 fixture 测试代替软件兼容性验证。

NSIS 参数依据：[官方安装器参数说明](https://nsis.sourceforge.io/Which_command_line_parameters_can_be_used_to_configure_installers)。

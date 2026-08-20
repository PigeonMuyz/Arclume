# Procyon 内置 Wine 源码与构建

这里保存可复现地维护 Procyon 内置 Wine 运行时所需的源码基线、补丁和脚本。

当前基线是 CodeWeavers 公开发布的 CrossOver 26.3.0 FOSS 源码包，其中的 Wine 版本为 11.0；版本、下载地址和 SHA-256 固定在 [`CROSSOVER_SOURCE.lock`](CROSSOVER_SOURCE.lock) 中。它与当前内置运行时返回的 `wine-11.0` 对应。

`RUNTIME_VERSION` 是随 Procyon App 发布的内置运行时版本标记。每次替换运行时归档都必须递增它，并同步更新 `Procyon/Resources/OnlineGameDependencies/procyon-wine-runtime-version.txt`；App 启动时会以该标记校验应用支持目录中的已安装运行时，不一致时会自动以新归档完成原子更新，Games 前缀不会被移动或重建。

## 目录约定

| 路径 | 用途 | Git 状态 |
| --- | --- | --- |
| `wine/` | 解压后的 Wine 源码工作树 | 忽略 |
| `cache/` | 下载的官方源代码包 | 忽略 |
| `patches/` | 需要随产品保留的 Wine 源码补丁 | 提交 |
| `build/` | x86_64 编译目录和临时 staging 目录 | 忽略 |
| `dist/` | 新生成、等待验证的运行时归档 | 忽略 |

## 日常流程

首次取得或校验源码：

```bash
./script/sync_crossover_wine_source.sh
open RuntimeSource/wine
```

若需要丢弃工作树改动并恢复锁定的公开源码和已提交补丁：

```bash
./script/sync_crossover_wine_source.sh --reset
```

在已安装 Xcode Command Line Tools、Rosetta（Apple Silicon）和 x86_64 Homebrew 构建依赖的机器上构建候选运行时：

```bash
./script/build_bundled_wine_runtime.sh
```

脚本在 `dist/` 生成新的 `.tar.xz` 和 SHA-256；它不会自动覆盖 `Procyon/Resources/OnlineGameDependencies/` 中当前随 App 发布的归档。候选包应先经过启动器和游戏测试，再由维护者显式替换资源并重新打包 App。

构建会以当前已提交的运行时归档为 staging 基础，只覆盖 Wine 核心安装输出，因此保留归档内已有的 DXVK、wine-mono、包装脚本和运行时布局。D3DMetal 3/4 是由 Procyon 的运行时配置选择和注入的组件，而不是这里的 Wine 核心编译产物。

构建脚本会把当前运行时标记写入候选归档。将候选归档替换进 App 前，先递增上述两个位置的版本并确保两者一致。

构建和同步脚本不会修改 `~/Library/Application Support/Procyon/OnlineGameWinePrefixes/Games` 或任何用户游戏文件。

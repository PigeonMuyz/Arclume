# 改用 Steam 官方统一下载地址

- 根据用户要求，最终方案替代本次开发中尝试的多 CDN 轮换：只请求 `https://cdn.steamstatic.com/client/installer/SteamSetup.exe`，由 Steam 管理域名背后的分发，不固定厂商节点或套用 GitHub 镜像。
- 网络失败最多自动重试一次；保留中文错误、取消、100 MiB 上限、HTTP/HTTPS/文件头检查及手动安装包入口。
- 独立 Swift 下载检查使用应用同一下载实现，不执行安装程序、不改动容器；另做 Debug 构建 / PR preflight，不运行 XCTest。

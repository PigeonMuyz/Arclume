# YY 离屏软件渲染的 WebGL 停顿对照

- 组合参数已读回生效，但现场仍出现 SwiftShader 等待、WebGL ReadPixels 停顿与 ANGLE Vulkan 两分钟超时。
- 新增独立 `--run-osr-no-webgl` 诊断模式，只在上一组合模式上添加禁用 WebGL；保留原有模式与严格模块校验，并增加模式自检。
- 此选项可能使 WebGL 频道内容不可用；不是正式修复，不修改全局 CEF 或生产 Adapter。退出测试即撤回，不删除用户缓存或设置。

# 扩展手柄启动器横栏

- 接入扩展手柄时自动在左下角显示横向启动器栏；手柄断开后恢复原侧栏布局。
- LB/RB 按已保存顺序循环切换启动器，并自动滚动到当前选择项。
- 保留鼠标拖动启动器排序；弹窗、引导显示或应用进入后台时不响应手柄切换。
- 遵循系统“减少动态效果”偏好，横栏显示、隐藏及选中项滚动不使用动画。
- 本阶段不改 toolbar、OSS 或 Runtime。
- 兼容与回退：横栏复用现有游戏顺序和所选游戏偏好；回退手柄输入及横栏接入后恢复竖向侧栏，使用期间保存的顺序和选择仍由现有偏好保留。
- 验证：`./script/pr_preflight.sh` 通过（无签名 Debug 构建、Runtime 校验）。定向核心测试通过，共 14 项、3 套件：

  ```bash
  xcodebuild test -project Arclume.xcodeproj -scheme Arclume -testPlan ArclumeCore -destination 'platform=macOS' -derivedDataPath /tmp/arclume-controller-tests -only-testing:ArclumeTests/LauncherControllerSelectionTests -only-testing:ArclumeTests/LauncherSidebarInsertionTests -only-testing:ArclumeTests/LauncherLibraryOrderTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= SWIFT_EMIT_LOC_STRINGS=NO
  ```

- 未实测：真实手柄插拔及 UI 交互；仍需在真机核对布局切换、LB/RB、弹窗/引导/后台门控、自动滚动、鼠标拖动与开始按钮无遮挡。

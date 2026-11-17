# 修复与优化报告

## 修复项汇总

### 1. 移除初始三个默认定时任务
- 修改 `lib/services/database_service.dart` 中的 `loadTasks` 方法，当数据库中无定时任务时直接返回空列表，不再默认写入三个检测任务。

### 2. 支持通过对话注册定时任务
- 在 `lib/services/agent_service.dart` 的系统提示词中注入任务注册指令规范。
- 在 `lib/providers/app_state_provider.dart` 中增加对用户输入指令（`注册定时 <名称> <周期> [类型]`）以及对模型输出代码块（```task ... ```）的自动解析与注册逻辑。

### 3. 统一顶栏与内容区背景颜色
- 在 `lib/theme/openclaw_theme.dart` 中将 `headerBackground` 设置为与 `background` 严格一致，消除顶栏与内容区之间的色彩突兀感。

### 4. 修复主题色切换失效问题
- 修复 `OpenClawTheme.buildTheme` 在构建时直接修改全局静态变量导致明亮主题被暗黑主题覆盖的问题。
- 将 `OpenClawTheme.isDark` 的同步绑定至 `AppStateProvider.isDarkTheme`，并在设置页面点击主题时即时生效。

### 5. 移除主页概念与多余导航
- 移除侧边栏与对话页面中的“主页”相关标题与导航标签，直接展示对话内容。
- 新建会话时直接保持在当前对话视图，不再跳转至任何无关页面。

### 6. 管控聊天气泡与输入区域
- 为聊天气泡添加最大宽度约束（屏幕宽度的 70%），在大屏分辨率下呈现合理布局。
- 将消息头像从占位文本替换为规范的图标。
- 优化输入框边距与圆角设计。

### 7. 解决窗口启动闪烁与位移缩放问题
- 修正 `windows/runner/win32_window.cpp`，去除窗口创建时的 `WS_VISIBLE` 属性。
- 移除 `windows/runner/main.cpp` 中的显式 `window.Show()` 调用。
- 调整 `lib/main.dart` 启动流程，在 `waitUntilReadyToShow` 就绪后再统一居中显示，彻底解决窗口从小变大、位置跳动与背景色闪烁问题。

### 8. 移除底部浮动提示
- 移除各页面中的 `ScaffoldMessenger.showSnackBar` 底部弹出提示。
- 移除对话空状态下的冗余提示文本，保持界面干净清爽。

### 9. 支持输入框回车发送消息
- 在输入框组件外层增加按键事件拦截，按 Enter 键直接触发消息发送，按 Shift + Enter 键进行换行输入。

### 10. 完善 macOS 系统兼容性
- 更新 `macos/Runner/Release.entitlements` 配置，开放网络客户端与服务端通信权限，关闭沙盒限制以确保本地数据库与网关服务正常运行。

### 11. 整体用户体验细节优化
- 顶栏增加清除当前会话历史快捷操作按钮。
- 各操作按钮文本进行精简，去重冗余修饰词。

### 12. 替换应用默认图标并剥离多余标识
- 生成全新的现代几何红调应用图标与托盘图标，替换 Windows 与 macOS 工程中的原生默认图标。
- 检查并剥除所有前端界面中直接出现的名称标识，直接显示实际状态与内容。

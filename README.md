# 桌面智能助手

基于 Flutter 开发的跨平台桌面智能助手客户端，支持对话交互、定时任务管理、本地插件扩展及内置网关服务。

## 功能

- 多会话对话交互，支持 Markdown 渲染与实时流式输出
- 基于 Cron 的定时计划任务调度与执行历史记录
- 支持在对话中通过指令让智能助手注册定时任务
- 插件系统，支持扫描、管理与运行本地脚本
- 本地 HTTP 与 WebSocket 双向网关服务
- 系统托盘驻留与后台运行
- 明亮与暗黑双主题无缝切换
- 兼容 Windows 与 macOS 桌面环境

## 技术栈

| 模块 | 技术选型 |
|------|----------|
| 客户端框架 | Flutter (Desktop) |
| 本地存储 | SQLite (sqflite_common_ffi) |
| 实时通信 | WebSocket |
| 任务调度 | Cron 调度引擎 |
| 状态管理 | Provider |
| 窗口管理 | window_manager |
| 系统托盘 | tray_manager |

## 项目结构

```
lib/
  main.dart                       # 应用启动入口与窗口初始化
  models/
    chat_message_model.dart       # 对话消息模型
    chat_session_model.dart       # 会话模型
    gateway_config.dart           # 网关与应用配置模型
    scheduled_task_model.dart     # 定时任务模型
    skill_model.dart              # 插件模型
    task_log_model.dart           # 任务日志模型
  providers/
    app_state_provider.dart       # 全局状态管理
  services/
    agent_service.dart            # 模型服务调用与流式通信
    cron_scheduler_service.dart   # 定时任务调度器
    database_service.dart         # SQLite 数据持久化
    gateway_server.dart           # 本地 HTTP/WS 网关
    skill_service.dart            # 插件解析与执行
    storage_service.dart          # 本地文件存储
    task_service.dart             # 任务管理服务
    tray_service.dart             # 系统托盘服务
  theme/
    agenthub_theme.dart           # 全局主题与颜色定义
  utils/
    path_utils.dart               # 跨平台路径工具
  views/
    chat_view.dart                # 对话交互视图
    home_view.dart                # 主布局与侧边栏导航
    settings_view.dart            # 系统设置视图
    skills_view.dart              # 插件管理视图
    tasks_view.dart               # 定时任务视图
skills/                           # 内置插件目录
bin/
  agenthub.dart                   # 命令行入口
```

## 构建运行

### 环境要求

- Flutter SDK >= 3.7.0
- Windows 10+ 或 macOS 12+

### Windows

```bash
flutter pub get
flutter run -d windows
```

构建发布版本：

```bash
flutter build windows --release
```

### macOS

```bash
flutter pub get
flutter run -d macos
```

构建发布版本：

```bash
flutter build macos --release
```

## 配置项

应用启动后可在设置界面中进行如下配置：

| 配置项 | 说明 | 初始值 |
|--------|------|--------|
| 服务地址 | 大模型 API 服务接口基地址 | 空 |
| 访问密钥 | 模型服务鉴权密钥 | 空 |
| 模型 | 目标模型名称 | 空 |
| 端口 | 本地网关监听端口 | 18789 |
| 自动启动 | 启动应用时自动运行本地网关 | 开启 |
| 插件目录 | 外部插件目录路径 | 空 |
| 主题 | 明亮 / 暗黑模式切换 | 明亮 |
| 最小化到托盘 | 关闭窗口时最小化至系统托盘 | 开启 |

## 对话指令

在对话输入框中支持直接输入快捷指令：

- `注册定时 <任务名称> <周期> [类型]`：快速创建定时任务
- `运行 <插件名称>`：直接调用已安装插件
- `状态`：查看当前网关、任务与插件状态
- `插件`：列出当前全部可用插件
- `帮助`：显示指令帮助说明

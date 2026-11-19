# AgentHub 项目当前状态与未完成事项清单

## 一、 最新代码与功能实现汇总

1. **命名与界面规范统一**
   - 移除原先冗余的旧版命名，全工程规范统一命名为 AgentHub。
   - 界面配色统一交由 [agenthub_theme.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/theme/agenthub_theme.dart) 管理，顶栏与背景严格对齐，支持明亮与暗黑两套规范主题。

2. **数据持久化与真实数据体系**
   - 桌面端数据统一使用本地 SQLite 数据库存储（[database_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/database_service.dart)），本地数据文件位于 `~/.agenthub/agenthub.db`。
   - 包含数据表：
     - `sessions`：会话列表
     - `messages`：消息历史
     - `scheduled_tasks`：定时任务
     - `task_logs`：真实任务执行日志
     - `configs`：系统配置
   - 彻底剔除虚假/预设测试数据，保证初始数据纯净。

3. **会话与对话交互功能（已实现）**
   - **会话重命名**：侧边栏选中会话后提供重命名编辑按钮，弹出输入框修改并保存至 SQLite。
   - **失败重试**：当助手消息返回错误状态时，展示重试按钮，一键重新请求。
   - **内容复制支持**：对话文本全面支持划选自由复制（`SelectableText` 与 `selectable: true`），并在每条气泡底部提供一键全量复制按钮，点击后即时反馈复制状态。
   - **上下文滑动窗口**：请求大模型时自动截取最近 20 条消息作为上下文，防止 Token 溢出。
   - **全局消息搜索**：顶栏搜索按钮支持检索所有历史会话的消息文本并一键跳转。
   - **倒序列表布局**：进入会话首帧直达底部，消除渲染抖动与下沉。
   - **快捷回车发送**：支持 Enter 直接发送、Shift+Enter 换行以及流式生成主动中止。
   - **窗口居中与显隐尺寸一致**：原生层与 Flutter 层统一固定 `1440x900` 居中展示，彻底消除 `maximize()` 导致的偏移右侧以及隐藏/唤出时窗口尺寸突变问题。
   - **托盘点击防抖与激活优化**：托盘点击智能识别前台激活状态与 250ms 防抖，失焦时单击直接拉至最前台，彻底解决偶发点击两次的问题。

4. **定时计划任务功能（已实现）**
   - **任务修改与二次编辑**：操作列中增加编辑按钮，支持修改任务名称、Cron 表达式、任务类型及执行命令。
   - **任务运行日志管理**：支持查看执行耗时与状态结果，并在日志底部提供一键清空日志操作。
   - **原生 Cron 调度服务**（[cron_scheduler_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/cron_scheduler_service.dart)）：基于标准 Cron 表达式进行底层调度，支持网关检测、插件扫描、系统命令执行及 7 天过期数据自动清理。

5. **Claude Code 环境管理与多任务 AI 编程工作台（已实现）**
   - **环境检测与安装引导**（[claude_env_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/claude_env_service.dart)）：
     - 自动检测本机 Claude Code 是否安装、获取绝对路径及版本号。
     - 自动探测 Node.js 环境，未安装时提供一键复制命令与指引。
   - **Profile 多账号切换与隔离**（[claude_profile_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/claude_profile_service.dart)）：
     - 借鉴 CCSwitch 架构机制，为每个 Profile 分配独立的专用配置目录（`~/.agenthub/claude_profiles/<id>`），启动时通过 `CLAUDE_CONFIG_DIR` 环境变量实现物理级配置与 OAuth 凭据隔离。
     - 支持 OAuth 与 API Key 两种授权模式，支持自定义模型名与权限模式。
   - **安全凭证存储**（[credential_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/credential_service.dart)）：
     - 基于系统底层 Keychain / Credential Manager 安全存储 API Key，绝不明文写入 JSON 或 SQLite。
   - **多任务工作台调度**（[claude_process_manager.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/claude_process_manager.dart) 与 [claude_manager_view.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/views/claude_manager_view.dart)）：
     - 每个工作台实例绑定独立的工作目录、Profile 环境变量、会话 ID（支持 `--resume` 上下文恢复）。
     - 支持多实例并行启动，通过 `-p --output-format stream-json` 实时捕获 NDJSON 流并在终端窗口实时滚动输出。
     - 具备任务状态监控与主动中止执行能力。
   - **文件与图片附件输入**（[attachment_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/attachment_service.dart) 与 [attachment_input.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/widgets/attachment_input.dart)）：
     - 支持图片（png/jpg/webp）、文本文档（txt/md/json 等）与源代码文件。
     - 支持文件选择器多选、桌面文件直接拖入输入区、剪贴板屏幕截图快捷粘贴。
     - 自动将附件暂存至工作目录并拼接入 prompt 供 Claude Code 视觉及读取工具解析。
   - **会话两阶段软删除与自动清理**（[trash_view.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/views/trash_view.dart)）：
     - 删除会话时写入 `deleted_at` 标记软删除，界面即时隐藏并提示用户。
     - 提供专属回收站页面，支持随时恢复会话或彻底物理删除。
     - 启动时及系统定时任务自动物理清理超过 7 天的超期已删会话与实例数据。

6. **插件扩展体系（已实现）**
   - **执行输出展示**：插件手动执行结果使用等宽字体终端样式弹窗进行展示。
   - **插件加载与管理**（[skill_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/skill_service.dart)）：支持扫描、启停、执行及通过 Git 仓库克隆安装。

7. **系统设置与参数配置（已实现）**
   - **网络代理配置**：增加 HTTP / HTTPS 网络代理输入项。
   - **模型参数调节**：增加温度（temperature）与 Top_P 采样参数配置。
   - **数据重置**：常规设置中增加清空全部历史会话数据操作，带二次确认弹窗。
   - **主题模式深度持久化与预载**：启动时在第一帧前完成 SQLite 配置读取，且设置页明暗模式卡片与全局真实状态 100% 绑定，彻底杜绝重启变亮色或设置保存写回默认值的缺陷。

8. **微信接入通道与消息自动回复（已实现）**
   - **独立服务对接**（[wechat_channel_service.dart](file:///Users/rong.chen/data/yuanzhijia/agenthub/lib/services/wechat_channel_service.dart)）：基于腾讯官方 iLink 机器人协议直连，支持二维码获取、扫码状态轮询、消息拉取与消息回复发送。
   - **自主选择与非强制接入**：通道默认不直接自启，由用户在顶栏快捷入口或系统设置面板中主动开启。
   - **自动回复开关控制**：用户可选择是否启动大模型自动回复微信接收到的消息。
   - **未读与已读消息标识**：
     - 侧边栏“对话”项与会话标题右侧显示全局未读消息徽标。
     - 会话列表中每个会话项右侧展示未读数量红底角标或已读状态。
     - 点击会话即自动将未读状态标记为已读并同步写入 SQLite。
     - 专属通道标识区分普通内部会话与微信渠道会话。

---

## 二、 后续待扩展事项

1. **工程自动化打包与交付发布**
   - [ ] 编写 macOS DMG 自动化打包与签名脚本。
   - [ ] 编写 Windows 安装包自动化构建脚本。
2. **插件生态拓展**
   - [ ] 视需要增加官方插件市场在线浏览与一键安装能力。

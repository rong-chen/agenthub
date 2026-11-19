import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../models/attachment.dart';
import '../models/checkpoint_model.dart';
import '../models/claude_profile.dart';
import '../models/gateway_config.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../models/skill_model.dart';
import '../models/scheduled_task_model.dart';
import '../models/task_log_model.dart';
import '../services/claude_process_manager.dart';
import '../services/claude_profile_service.dart';
import '../services/checkpoint_service.dart';
import '../services/database_service.dart';
import '../services/skill_service.dart';
import '../services/agent_service.dart';
import '../services/cron_scheduler_service.dart';
import '../services/gateway_server.dart';
import '../services/tray_service.dart';
import '../services/wechat_channel_service.dart';
import '../theme/agenthub_theme.dart';

/// 全局应用状态管理
class AppStateProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService.instance;
  final SkillService _skillService = SkillService();
  final AgentService _agentService = AgentService();
  final ClaudeProcessManager _processManager = ClaudeProcessManager.instance;
  final ClaudeProfileService _profileService = ClaudeProfileService.instance;
  final CheckpointService _checkpointService = CheckpointService.instance;
  final CronSchedulerService _cronService = CronSchedulerService.instance;
  late final GatewayServer _gatewayServer;

  int _currentTabIndex = 0;
  final Set<String> _busySessionIds = {};
  final Set<String> _abortedSessionIds = {};
  final Map<String, String> _sessionStreamMsgIds = {};

  bool _isGatewayOnline = false;
  String _gatewayStatusMessage = '未启动';
  GatewayConfig _config = GatewayConfig.initial();
  List<SkillModel> _skills = [];
  List<ScheduledTaskModel> _tasks = [];
  List<TaskLogModel> _taskLogs = [];

  // 多会话管理
  List<ChatSessionModel> _sessions = [];
  String? _activeSessionId;

  WebSocket? _wsClient;

  AppStateProvider() {
    _gatewayServer = GatewayServer(
      skillService: _skillService,
      agentService: _agentService,
    );
  }

  int get currentTabIndex => _currentTabIndex;

  /// 检查指定会话是否正在运行任务
  bool isSessionBusy(String? sessionId) => sessionId != null && _busySessionIds.contains(sessionId);

  /// 当前活跃会话是否忙碌
  bool get isBusy => isSessionBusy(_activeSessionId);
  bool get isGatewayOnline => _isGatewayOnline;
  bool get isGatewayRunning => _gatewayServer.isRunning;
  String get gatewayStatusMessage => _gatewayStatusMessage;
  int get gatewayPort => _config.gatewayPort;
  GatewayConfig get config => _config;
  List<SkillModel> get skills => _skills;
  List<ScheduledTaskModel> get tasks => _tasks;
  List<TaskLogModel> get taskLogs => _taskLogs;
  List<ChatSessionModel> get sessions => _sessions;
  String? get activeSessionId => _activeSessionId;
  bool get isDarkTheme => _config.themeMode == 'dark';
  WechatChannelService get wechatService => WechatChannelService.instance;

  /// 全局未读消息总数
  int get totalUnreadCount => _sessions.fold(0, (sum, s) => sum + s.unreadCount);

  /// 当前活跃会话的消息列表
  List<ChatMessageModel> get messages {
    if (_activeSessionId == null) {
      return [];
    }
    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == _activeSessionId,
      orElse: () => null,
    );
    return session?.messages ?? [];
  }

  static const MethodChannel _windowThemeChannel = MethodChannel('agenthub/window_theme');

  /// 同步原生窗口标题栏主题
  Future<void> _syncWindowTheme(bool isDark) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await windowManager.setBrightness(isDark ? Brightness.dark : Brightness.light);
      }
      if (Platform.isWindows) {
        await _windowThemeChannel.invokeMethod('setDarkTheme', {'isDark': isDark});
      }
    } catch (_) {}
  }

  /// 初始化加载所有配置、技能、定时任务、会话，并按配置启动内置网关
  Future<void> initialize() async {
    _config = await _dbService.loadConfig();
    final isDark = _config.themeMode == 'dark';
    AgentHubTheme.isDark = isDark;
    await _syncWindowTheme(isDark);

    // 自动物理清理超过 7 天的软删除数据
    try {
      await _dbService.purgeExpiredSessions();
      await _dbService.purgeExpiredInstances();
    } catch (_) {}

    _sessions = await _dbService.loadSessions();
    _tasks = await _dbService.loadTasks();
    _taskLogs = await _dbService.loadTaskLogs();
    await reloadSkills();

    // 自动选中最近的会话，或创建默认会话
    if (_sessions.isNotEmpty) {
      _activeSessionId = _sessions.first.id;
    } else {
      await createNewSession();
    }

    if (_config.autoStartGateway) {
      await startLocalGateway();
    } else {
      await checkGatewayStatus();
    }

    // 启动真实 Cron 调度
    _syncCronScheduler();

    // 监听微信通道状态变更并绑定持久化存储
    WechatChannelService.instance.addListener(notifyListeners);
    WechatChannelService.instance.onAuthenticated = (token, name) async {
      await _dbService.saveWechatToken(token, name);
    };

    if (_config.wechatChannelEnabled) {
      final savedAuth = await _dbService.loadWechatToken();
      final savedToken = savedAuth['botToken'];
      final savedName = savedAuth['botName'] ?? '微信助手';
      if (savedToken != null && savedToken.isNotEmpty) {
        await WechatChannelService.instance.restoreSession(
          botToken: savedToken,
          botName: savedName,
          autoReply: _config.wechatAutoReply,
          onMessage: _handleInboundWechatMessage,
        );
      } else {
        await startWechatChannel();
      }
    }

    _updateTrayMenu();
    notifyListeners();
  }

  // ==================== 主题切换 ====================

  /// 切换明暗主题
  Future<void> toggleTheme() async {
    _config.themeMode = isDarkTheme ? 'light' : 'dark';
    final isDark = _config.themeMode == 'dark';
    AgentHubTheme.isDark = isDark;
    await _syncWindowTheme(isDark);
    await _dbService.saveConfig(_config);
    notifyListeners();
  }

  // ==================== 会话管理 ====================

  /// 创建新会话，支持聊天模式与代码模式，并自动切换到对话标签页
  Future<void> createNewSession({
    String sessionMode = 'chat',
    String? workDir,
    String? profileId,
    String? title,
  }) async {
    final now = DateTime.now();
    final defaultTitle = sessionMode == 'code' ? '代码会话' : '新会话';
    final session = ChatSessionModel(
      id: 'session_${now.millisecondsSinceEpoch}',
      title: title ?? defaultTitle,
      createdAt: now,
      updatedAt: now,
      sessionMode: sessionMode,
      workDir: workDir,
      profileId: profileId,
    );
    await _dbService.insertSession(session);
    _sessions.insert(0, session);
    _activeSessionId = session.id;
    _currentTabIndex = 0; // 自动跳转到对话页
    notifyListeners();
  }

  /// 切换到指定会话
  void switchSession(String sessionId) {
    if (_activeSessionId == sessionId) {
      final session = _sessions.cast<ChatSessionModel?>().firstWhere(
        (s) => s?.id == sessionId,
        orElse: () => null,
      );
      if (session != null && session.unreadCount > 0) {
        session.unreadCount = 0;
        _dbService.markSessionAsRead(sessionId);
        notifyListeners();
      }
      return;
    }
    _activeSessionId = sessionId;
    _currentTabIndex = 0;

    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == sessionId,
      orElse: () => null,
    );
    if (session != null && session.unreadCount > 0) {
      session.unreadCount = 0;
      _dbService.markSessionAsRead(sessionId);
    }
    notifyListeners();
  }

  /// 软删除指定会话，优先选中最靠近的相邻会话
  Future<void> deleteSession(String sessionId) async {
    final deleteIndex = _sessions.indexWhere((s) => s.id == sessionId);
    await _dbService.softDeleteSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);

    if (_activeSessionId == sessionId) {
      if (_sessions.isEmpty) {
        await createNewSession();
      } else {
        // 选中最靠近的一个会话：优先保留当前下标（原下一个），若已至末尾则选中前一个
        final nextIndex = (deleteIndex >= 0 && deleteIndex < _sessions.length)
            ? deleteIndex
            : _sessions.length - 1;
        _activeSessionId = _sessions[nextIndex].id;
      }
    }
    notifyListeners();
  }

  /// 恢复指定软删除的会话
  Future<void> restoreSession(String sessionId) async {
    await _dbService.restoreSession(sessionId);
    _sessions = await _dbService.loadSessions();
    if (_activeSessionId == null && _sessions.isNotEmpty) {
      _activeSessionId = _sessions.first.id;
    }
    notifyListeners();
  }

  /// 彻底物理删除会话
  Future<void> hardDeleteSession(String sessionId) async {
    await _dbService.deleteSession(sessionId);
    _sessions = await _dbService.loadSessions();
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }
    notifyListeners();
  }

  /// 读取已软删除的会话列表
  Future<List<ChatSessionModel>> loadDeletedSessions() async {
    return await _dbService.loadDeletedSessions();
  }

  /// 重命名指定会话标题
  Future<void> renameSession(String sessionId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;

    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == sessionId,
      orElse: () => null,
    );
    if (session != null) {
      session.title = trimmed;
      session.updatedAt = DateTime.now();
      await _dbService.updateSession(session);
      notifyListeners();
    }
  }

  /// 重试上一条失败的用户消息
  Future<void> retryLastMessage() async {
    if (isSessionBusy(_activeSessionId) || _activeSessionId == null) return;

    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == _activeSessionId,
      orElse: () => null,
    );
    if (session == null || session.messages.isEmpty) return;

    // 找到最后一条用户消息
    ChatMessageModel? lastUserMsg;
    for (int i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].role == MessageRole.user) {
        lastUserMsg = session.messages[i];
        break;
      }
    }
    if (lastUserMsg == null) return;

    // 如果最后一条是 assistant 的错误消息，先从列表中移除
    if (session.messages.isNotEmpty && session.messages.last.role == MessageRole.assistant) {
      session.messages.removeLast();
      await _dbService.clearSessionMessages(_activeSessionId!);
      // 重新把剩余的消息写回
      for (final m in session.messages) {
        await _dbService.saveMessage(_activeSessionId!, m);
      }
    }

    // 重新发起请求
    await sendMessage(lastUserMsg.content);
  }

  /// 清空全部会话与消息历史记录
  Future<void> resetAllSessions() async {
    await _dbService.resetAllSessions();
    _sessions.clear();
    _activeSessionId = null;
    await createNewSession();
  }

  /// 全局模糊检索消息历史
  Future<List<Map<String, dynamic>>> searchMessages(String query) async {
    return await _dbService.searchMessages(query);
  }

  /// 清空当前会话的消息
  Future<void> clearChatHistory() async {
    if (_activeSessionId == null) {
      return;
    }
    await _dbService.clearSessionMessages(_activeSessionId!);
    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == _activeSessionId,
      orElse: () => null,
    );
    session?.messages.clear();
    notifyListeners();
  }

  /// 根据首条消息内容自动设定会话标题
  void _autoUpdateSessionTitle(ChatSessionModel session, String firstUserMsg) {
    if (session.title != '新会话') {
      return;
    }
    final title = firstUserMsg.length > 20 ? '${firstUserMsg.substring(0, 20)}...' : firstUserMsg;
    session.title = title;
    session.updatedAt = DateTime.now();
    _dbService.updateSession(session);
  }

  // ==================== 网关管理 ====================

  /// 启动本地内置网关
  Future<bool> startLocalGateway() async {
    final result = await _gatewayServer.start(
      port: _config.gatewayPort,
      getConfig: () => _config,
      getSkills: () => _skills,
    );

    if (result.isSuccess) {
      _isGatewayOnline = true;
      _gatewayStatusMessage = result.message;
      _updateTrayMenu();
      notifyListeners();
      return true;
    }

    final isAlreadyOnline = await _agentService.checkGatewayHealth(_config.gatewayPort);
    if (isAlreadyOnline) {
      _isGatewayOnline = true;
      _gatewayStatusMessage = '网关已在端口 ${_config.gatewayPort} 运行中';
      _updateTrayMenu();
      notifyListeners();
      return true;
    }

    _isGatewayOnline = false;
    _gatewayStatusMessage = result.message;
    _updateTrayMenu();
    notifyListeners();
    return false;
  }

  /// 停止本地内置网关
  Future<void> stopLocalGateway() async {
    await _closeWsClient();
    await _gatewayServer.stop();
    _isGatewayOnline = false;
    _gatewayStatusMessage = '网关已停止';
    _updateTrayMenu();
    notifyListeners();
  }

  /// 关闭 WebSocket 客户端连接
  Future<void> _closeWsClient() async {
    if (_wsClient != null) {
      try {
        await _wsClient!.close();
      } catch (_) {}
      _wsClient = null;
    }
  }

  /// 检查网关连接状态
  Future<void> checkGatewayStatus() async {
    _isGatewayOnline = await _agentService.checkGatewayHealth(_config.gatewayPort);
    _gatewayStatusMessage = _isGatewayOnline
        ? '网关在线 (端口 ${_config.gatewayPort})'
        : '网关未启动';
    _updateTrayMenu();
    notifyListeners();
  }

  /// 更新托盘菜单信息
  void _updateTrayMenu() {
    final activeCount = _skills.where((s) => s.isEnabled).length;
    TrayService.instance.updateContextMenu(
      activeSkillsCount: activeCount,
      isGatewayConnected: _isGatewayOnline,
      port: _config.gatewayPort,
    );
  }

  // ==================== 导航与技能 ====================

  /// 切换侧边栏导航标签页
  void selectTab(int index) {
    if (_currentTabIndex == index) {
      return;
    }
    _currentTabIndex = index;
    notifyListeners();
  }

  /// 重新扫描所有技能目录
  Future<void> reloadSkills() async {
    _skills = await _skillService.loadAllSkills(
      customPath: _config.customSkillsPath,
    );
    _updateTrayMenu();
    notifyListeners();
  }

  /// 安装新技能到本地
  Future<String> installSkill(String source) async {
    final message = await _skillService.installSkill(source: source);
    await reloadSkills();
    return message;
  }

  /// 卸载本地技能
  Future<bool> uninstallSkill(String skillName) async {
    final ok = await _skillService.uninstallSkill(skillName);
    if (ok) {
      await reloadSkills();
    }
    return ok;
  }

  /// 切换指定技能的启用状态
  void toggleSkill(SkillModel skill, bool enabled) {
    skill.isEnabled = enabled;
    _updateTrayMenu();
    notifyListeners();
  }

  /// 执行指定插件
  Future<String> executeSkill(SkillModel skill, [String? customCommand]) async {
    return await _skillService.runSkill(skill, customCommand);
  }

  /// 创建新本地插件
  Future<bool> createSkill({
    required String name,
    required String description,
    required String instructions,
  }) async {
    final ok = await _skillService.createSkill(
      name: name,
      description: description,
      instructions: instructions,
    );
    if (ok) {
      await reloadSkills();
    }
    return ok;
  }

  // ==================== Cron 定时任务 ====================

  /// 重新加载所有计划任务
  Future<void> reloadTasks() async {
    _tasks = await _dbService.loadTasks();
    _taskLogs = await _dbService.loadTaskLogs();
    _syncCronScheduler();
    notifyListeners();
  }

  /// 同步 Cron 调度器
  void _syncCronScheduler() {
    _cronService.syncTasks(
      _tasks,
      gatewayPort: _config.gatewayPort,
      onSkillsReload: () => reloadSkills(),
      onTaskExecuted: () async {
        _tasks = await _dbService.loadTasks();
        _taskLogs = await _dbService.loadTaskLogs();
        notifyListeners();
      },
    );
  }

  /// 切换计划任务激活开关
  Future<void> toggleTask(String taskId, bool isEnabled) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      _tasks[index].isEnabled = isEnabled;
      await _dbService.saveTask(_tasks[index]);
      _syncCronScheduler();
      notifyListeners();
    }
  }

  /// 手动触发执行一次计划任务
  Future<void> triggerTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index >= 0) {
      await _cronService.executeTask(
        _tasks[index],
        gatewayPort: _config.gatewayPort,
        onSkillsReload: () => reloadSkills(),
      );
      _tasks = await _dbService.loadTasks();
      _taskLogs = await _dbService.loadTaskLogs();
      notifyListeners();
    }
  }

  /// 新增一个计划任务
  Future<void> addTask(ScheduledTaskModel task) async {
    task.nextRun = _cronService.calculateNextRun(task.schedule);
    await _dbService.saveTask(task);
    _tasks = await _dbService.loadTasks();
    _syncCronScheduler();
    notifyListeners();
  }

  /// 更新已有计划任务
  Future<void> updateTask(ScheduledTaskModel task) async {
    task.nextRun = _cronService.calculateNextRun(task.schedule);
    await _dbService.saveTask(task);
    _tasks = await _dbService.loadTasks();
    _syncCronScheduler();
    notifyListeners();
  }

  /// 删除指定计划任务
  Future<void> removeTask(String taskId) async {
    await _dbService.deleteTask(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    _syncCronScheduler();
    notifyListeners();
  }

  /// 清空任务运行历史日志
  Future<void> clearTaskLogs({String? taskId}) async {
    await _dbService.clearTaskLogs(taskId: taskId);
    _taskLogs = await _dbService.loadTaskLogs();
    notifyListeners();
  }

  // ==================== 配置保存与更新 ====================

  /// 保存并更新设置
  Future<void> updateConfig(GatewayConfig newConfig) async {
    final portChanged = _config.gatewayPort != newConfig.gatewayPort;
    final autoStartChanged = _config.autoStartGateway != newConfig.autoStartGateway;

    _config = newConfig;
    final isDark = _config.themeMode == 'dark';
    AgentHubTheme.isDark = isDark;
    await _syncWindowTheme(isDark);
    await _dbService.saveConfig(_config);

    await reloadSkills();

    if (portChanged || autoStartChanged) {
      await stopLocalGateway();
      if (_config.autoStartGateway) {
        await startLocalGateway();
      }
    } else {
      await checkGatewayStatus();
    }

    notifyListeners();
  }

  // ==================== 消息收发 ====================

  /// 发送用户消息并进行实时流式交互（支持聊天模式与代码模式，支持多会话独立并行）
  Future<void> sendMessage(String text, {List<Attachment> attachments = const [], String? targetSessionId}) async {
    final currentSessionId = targetSessionId ?? _activeSessionId;
    if (currentSessionId == null) {
      return;
    }
    if (isSessionBusy(currentSessionId)) {
      return;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }

    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == currentSessionId,
      orElse: () => null,
    );
    if (session == null) {
      return;
    }

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    _sessionStreamMsgIds[currentSessionId] = msgId;
    _abortedSessionIds.remove(currentSessionId);

    final userMessage = ChatMessageModel(
      id: msgId,
      role: MessageRole.user,
      content: trimmed.isNotEmpty ? trimmed : '发送了附件',
      timestamp: DateTime.now(),
      status: MessageStatus.done,
      attachments: attachments.map((a) => a.fileName).toList(),
    );
    session.messages.add(userMessage);
    await _dbService.saveMessage(currentSessionId, userMessage);

    // 自动从首条用户消息更新会话标题
    if (trimmed.isNotEmpty) {
      _autoUpdateSessionTitle(session, trimmed);
    }

    final assistantMsgId = '${msgId}_bot';
    final assistantMessage = ChatMessageModel(
      id: assistantMsgId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.streaming,
    );
    session.messages.add(assistantMessage);

    _busySessionIds.add(currentSessionId);
    notifyListeners();

    // 代码模式：调用绑定的独立 Claude Code 实例执行任务并实时流式输出
    if (session.isCodeMode) {
      final workDir = session.workDir ?? Directory.current.path;
      try {
        final profiles = await _profileService.loadProfiles();
        ClaudeProfile? profile;
        if (session.profileId != null) {
          profile = profiles.cast<ClaudeProfile?>().firstWhere(
            (p) => p?.id == session.profileId,
            orElse: () => profiles.isNotEmpty ? profiles.first : null,
          );
        } else if (profiles.isNotEmpty) {
          profile = profiles.first;
        }

        if (profile == null) {
          assistantMessage.content = '未检测到可用配置，请先在【Claude 配置】中创建账号配置';
          assistantMessage.status = MessageStatus.error;
          await _dbService.saveMessage(currentSessionId, assistantMessage);
          return;
        }

        final instance = await _processManager.getOrCreateInstanceForSession(
          sessionId: session.id,
          profile: profile,
          workDir: workDir,
        );

        // 任务开始前捕获工作目录文件快照
        await _checkpointService.capturePreState(
          sessionId: session.id,
          messageId: assistantMsgId,
          workDir: workDir,
        );

        final stream = _processManager.executeTask(
          instanceId: instance.id,
          profile: profile,
          prompt: trimmed.isNotEmpty ? trimmed : '请查阅上传的文件附件',
          attachments: attachments,
        );

        await for (final event in stream) {
          if (_abortedSessionIds.contains(currentSessionId)) {
            assistantMessage.isThinking = false;
            break;
          }

          if (event.isThinking) {
            assistantMessage.isThinking = true;
            if (event.thinking != null && event.thinking!.isNotEmpty) {
              assistantMessage.thinking = (assistantMessage.thinking ?? '') + event.thinking!;
            }
          }

          if (event.type == 'assistant' && event.content != null && event.content!.isNotEmpty) {
            assistantMessage.isThinking = false;
            final incoming = event.content!;
            if (assistantMessage.content.isEmpty) {
              assistantMessage.content = incoming;
            } else if (!assistantMessage.content.contains(incoming)) {
              assistantMessage.content = '${assistantMessage.content}\n\n$incoming';
            }
          } else if (event.type == 'result' && event.content != null && event.content!.isNotEmpty) {
            assistantMessage.isThinking = false;
            final incoming = event.content!;
            if (assistantMessage.content.isEmpty) {
              assistantMessage.content = incoming;
            } else if (!assistantMessage.content.contains(incoming) && !incoming.contains(assistantMessage.content)) {
              assistantMessage.content = '${assistantMessage.content}\n\n$incoming';
            }
          } else if (event.type == 'tool_use') {
            assistantMessage.isThinking = false;
            assistantMessage.toolName = event.toolName;
            assistantMessage.toolInput = event.toolInput;
          } else if (event.type == 'tool_result' || event.toolOutput != null) {
            assistantMessage.toolOutput = event.toolOutput;
          } else if (event.type == 'error') {
            assistantMessage.isThinking = false;
            assistantMessage.content = event.content ?? '执行异常';
            assistantMessage.status = MessageStatus.error;
          }
          notifyListeners();
        }
      } catch (e) {
        assistantMessage.isThinking = false;
        assistantMessage.content = '执行出错: $e';
        assistantMessage.status = MessageStatus.error;
      } finally {
        assistantMessage.isThinking = false;
        if (assistantMessage.status != MessageStatus.error) {
          assistantMessage.status = MessageStatus.done;
        }

        // 任务完成后对比文件生成 Checkpoint 快照
        try {
          final ckpt = await _checkpointService.finalizeCheckpoint(
            sessionId: session.id,
            messageId: assistantMsgId,
            workDir: workDir,
          );
          if (ckpt != null) {
            assistantMessage.checkpointId = ckpt.id;
            assistantMessage.checkpoint = ckpt;
          }
        } catch (_) {}

        session.tokensUsed += (assistantMessage.content.length / 2.5).round();
        session.updatedAt = DateTime.now();
        await _dbService.updateSession(session);
        await _dbService.saveMessage(currentSessionId, assistantMessage);
        _busySessionIds.remove(currentSessionId);
        _abortedSessionIds.remove(currentSessionId);
        _sessionStreamMsgIds.remove(currentSessionId);
        notifyListeners();
      }
      return;
    }

    // 本地命令支持与快速响应
    if (trimmed.startsWith('/run ') || trimmed.startsWith('运行插件 ') || trimmed.startsWith('运行 ')) {
      final skillName = trimmed.replaceFirst(RegExp(r'^(/run|运行插件|运行)\s+'), '').trim();
      final skill = _skills.cast<SkillModel?>().firstWhere(
        (s) => s?.name.toLowerCase() == skillName.toLowerCase(),
        orElse: () => null,
      );
      if (skill != null) {
        final out = await _skillService.runSkill(skill);
        assistantMessage.content = out;
        assistantMessage.status = MessageStatus.done;
      } else {
        assistantMessage.content = '未找到插件: $skillName';
        assistantMessage.status = MessageStatus.done;
      }
    } else if (trimmed == '/status' || trimmed == '状态') {
      final activeTasks = _tasks.where((t) => t.isEnabled).length;
      final activeSkills = _skills.where((s) => s.isEnabled).length;
      assistantMessage.content = '网关: ${_isGatewayOnline ? "在线" : "未启动"}\n任务: $activeTasks 项\n插件: $activeSkills 项';
      assistantMessage.status = MessageStatus.done;
    } else if (trimmed == '/skills' || trimmed == '插件') {
      if (_skills.isEmpty) {
        assistantMessage.content = '暂无插件';
      } else {
        assistantMessage.content = _skills.map((s) => '- ${s.name}: ${s.description}').join('\n');
      }
      assistantMessage.status = MessageStatus.done;
    } else if (trimmed == '/help' || trimmed == '帮助') {
      assistantMessage.content = '支持的命令:\n- 运行 <名称>\n- 插件\n- 状态\n- 注册定时 <名称> <cron> <类型>';
      assistantMessage.status = MessageStatus.done;
    } else if (trimmed.startsWith('注册定时 ') || trimmed.startsWith('添加定时 ') || trimmed.startsWith('/schedule ')) {
      // 解析定时任务注册指令：注册定时 <名称> <cron表达式> [任务类型]
      final parts = trimmed.replaceFirst(RegExp(r'^(注册定时|添加定时|/schedule)\s+'), '').trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final taskName = parts[0];
        String actionType = 'gateway_check';
        String command = '';
        String cronExpr = '';

        if (parts.length >= 3 && (parts.last == 'gateway_check' || parts.last == 'skills_reload' || parts.last == 'shell_cmd')) {
          actionType = parts.last;
          cronExpr = parts.sublist(1, parts.length - 1).join(' ');
        } else {
          cronExpr = parts.sublist(1).join(' ');
        }

        final newTask = ScheduledTaskModel(
          id: 'task_${DateTime.now().millisecondsSinceEpoch}',
          name: taskName,
          schedule: cronExpr.isNotEmpty ? cronExpr : '*/30 * * * *',
          actionType: actionType,
          command: command,
          isEnabled: true,
        );
        await addTask(newTask);
        assistantMessage.content = '已注册定时任务: $taskName\n调度: ${newTask.schedule}\n类型: $actionType';
      } else {
        assistantMessage.content = '格式: 注册定时 <名称> <周期> [类型]';
      }
      assistantMessage.status = MessageStatus.done;
    } else if (_config.apiBaseUrl.trim().isEmpty || _config.apiKey.trim().isEmpty) {
      // 检查是否有匹配的本地插件
      final matchedSkill = _skills.cast<SkillModel?>().firstWhere(
        (s) => s != null && s.isEnabled && trimmed.toLowerCase().contains(s.name.toLowerCase()),
        orElse: () => null,
      );
      if (matchedSkill != null) {
        final out = await _skillService.runSkill(matchedSkill);
        assistantMessage.content = out;
        assistantMessage.status = MessageStatus.done;
      } else {
        assistantMessage.content = '请先在设置中配置服务地址与访问密钥';
        assistantMessage.status = MessageStatus.done;
      }
    } else {
      if (_isGatewayOnline) {
        await _sendViaWebSocket(msgId, trimmed, assistantMessage);
      } else {
        await _sendViaDirectStream(msgId, trimmed, assistantMessage, currentSessionId);
      }
    }

    assistantMessage.status = assistantMessage.status == MessageStatus.streaming
        ? MessageStatus.done
        : assistantMessage.status;
    await _dbService.saveMessage(currentSessionId, assistantMessage);

    // 若当前为微信渠道会话，将生成的回复推送回手机微信端
    if (session.channel == 'wechat' && assistantMessage.content.isNotEmpty) {
      final wxUserId = session.id.replaceFirst(RegExp(r'^wx_'), '');
      await WechatChannelService.instance.sendReply(wxUserId, assistantMessage.content);
    }

    // 解析 AI 回复中的定时任务注册指令
    await _tryRegisterTaskFromAiResponse(assistantMessage.content);

    // 更新会话活跃时间
    session.updatedAt = DateTime.now();
    await _dbService.updateSession(session);

    // 刷新会话排序
    _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    _busySessionIds.remove(currentSessionId);
    _abortedSessionIds.remove(currentSessionId);
    _sessionStreamMsgIds.remove(currentSessionId);
    notifyListeners();
  }

  /// 通过 WebSocket /ws 接口双向流式通信
  Future<void> _sendViaWebSocket(
    String sessionId,
    String prompt,
    ChatMessageModel assistantMessage,
  ) async {
    try {
      final wsUri = Uri.parse('ws://127.0.0.1:${_config.gatewayPort}/ws');
      final socket = await WebSocket.connect(wsUri.toString()).timeout(
        const Duration(seconds: 3),
      );
      _wsClient = socket;

      final completer = Completer<void>();
      final contentBuffer = StringBuffer();

      final validHistory = messages
          .where((m) => m.id != assistantMessage.id && m.status == MessageStatus.done)
          .map((m) => m.toJson())
          .toList();

      socket.add(jsonEncode({
        'type': 'chat',
        'id': sessionId,
        'content': prompt,
        'history': validHistory,
      }));

      socket.listen(
        (dynamic data) {
          try {
            final event = jsonDecode(data.toString()) as Map<String, dynamic>;
            final eventId = event['id']?.toString();
            if (eventId != null && eventId != sessionId) {
              return;
            }

            final eventType = event['type']?.toString();
            if (eventType == 'status') {
              if (contentBuffer.isEmpty) {
                assistantMessage.content = event['text']?.toString() ?? '';
                notifyListeners();
              }
              return;
            }

            if (eventType == 'delta') {
              contentBuffer.write(event['text']?.toString() ?? '');
              assistantMessage.content = contentBuffer.toString();
              notifyListeners();
              return;
            }

            if (eventType == 'done') {
              assistantMessage.content = contentBuffer.isNotEmpty
                  ? contentBuffer.toString()
                  : event['content']?.toString() ?? '';
              assistantMessage.status = MessageStatus.done;
              if (!completer.isCompleted) {
                completer.complete();
              }
              return;
            }

            if (eventType == 'aborted') {
              assistantMessage.content = contentBuffer.isNotEmpty
                  ? contentBuffer.toString()
                  : '[已中止]';
              assistantMessage.status = MessageStatus.done;
              if (!completer.isCompleted) {
                completer.complete();
              }
              return;
            }

            if (eventType == 'error') {
              assistantMessage.content = event['error']?.toString() ?? '执行错误';
              assistantMessage.status = MessageStatus.error;
              if (!completer.isCompleted) {
                completer.complete();
              }
              return;
            }
          } catch (_) {}
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      await completer.future;
    } catch (_) {
      await _sendViaDirectStream(sessionId, prompt, assistantMessage);
    } finally {
      await _closeWsClient();
    }
  }

  /// 本地直接流式生成调用
  Future<void> _sendViaDirectStream(
    String sessionId,
    String prompt,
    ChatMessageModel assistantMessage, [
    String? targetSessionId,
  ]) async {
    final sid = targetSessionId ?? _activeSessionId;
    final activeSkills = _skills.where((s) => s.isEnabled).toList();
    final session = sid != null ? _sessions.cast<ChatSessionModel?>().firstWhere((s) => s?.id == sid, orElse: () => null) : null;
    final validHistory = (session != null ? session.messages : messages)
        .where((m) => m.id != assistantMessage.id && m.status == MessageStatus.done)
        .toList();
    final contentBuffer = StringBuffer();

    await for (final event in _agentService.sendMessageStream(
      config: _config,
      history: validHistory,
      activeSkills: activeSkills,
      userPrompt: prompt,
      isAborted: () => sid != null && _abortedSessionIds.contains(sid),
    )) {
      final type = event['type']?.toString();
      if (type == 'status') {
        if (contentBuffer.isEmpty) {
          assistantMessage.content = event['text']?.toString() ?? '';
          notifyListeners();
        }
        continue;
      }

      if (type == 'delta') {
        contentBuffer.write(event['text']?.toString() ?? '');
        assistantMessage.content = contentBuffer.toString();
        notifyListeners();
        continue;
      }

      if (type == 'aborted') {
        assistantMessage.content = contentBuffer.isNotEmpty
            ? contentBuffer.toString()
            : '[已中止]';
        assistantMessage.status = MessageStatus.done;
        notifyListeners();
        return;
      }

      if (type == 'done') {
        assistantMessage.content = contentBuffer.isNotEmpty
            ? contentBuffer.toString()
            : event['content']?.toString() ?? '';
        assistantMessage.status = MessageStatus.done;
        notifyListeners();
        return;
      }

      if (type == 'error') {
        assistantMessage.content = event['error']?.toString() ?? '执行失败';
        assistantMessage.status = MessageStatus.error;
        notifyListeners();
        return;
      }
    }
  }

  /// 中止指定或当前正在进行的生成任务
  void abortCurrentGeneration([String? targetSessionId]) {
    final sid = targetSessionId ?? _activeSessionId;
    if (sid == null || !isSessionBusy(sid)) {
      return;
    }

    _abortedSessionIds.add(sid);

    // 中止 WebSocket 或 AgentService 请求
    final msgId = _sessionStreamMsgIds[sid];
    if (_wsClient != null && msgId != null) {
      try {
        _wsClient!.add(jsonEncode({
          'type': 'abort',
          'id': msgId,
        }));
      } catch (_) {}
    }

    // 中止代码模式下的独立 Claude Code 进程
    _processManager.killInstance('session_$sid');

    _busySessionIds.remove(sid);
    notifyListeners();
  }

  /// 回滚指定消息所关联的 Checkpoint 文件改动
  Future<bool> rollbackMessageCheckpoint(ChatMessageModel message) async {
    CheckpointModel? ckpt = message.checkpoint;
    if (ckpt == null && message.checkpointId != null) {
      ckpt = await _dbService.getCheckpointByMessageId(message.id);
    }
    if (ckpt == null || ckpt.isRolledBack) {
      return false;
    }

    final ok = await _checkpointService.rollback(ckpt);
    if (ok) {
      message.checkpoint = ckpt;
      message.checkpointId = ckpt.id;

      final rollbackMsg = ChatMessageModel(
        id: '${DateTime.now().millisecondsSinceEpoch}_rollback',
        role: MessageRole.system,
        content: '已成功回退本次改动，涉及文件已安全恢复至任务前版本。',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
      );
      final session = _sessions.cast<ChatSessionModel?>().firstWhere(
        (s) => s?.id == ckpt!.sessionId,
        orElse: () => null,
      );
      if (session != null) {
        session.messages.add(rollbackMsg);
        await _dbService.saveMessage(session.id, rollbackMsg);
      }
      notifyListeners();
    }
    return ok;
  }

  /// 解析并自动注册 AI 输出中的定时任务指令块
  Future<void> _tryRegisterTaskFromAiResponse(String content) async {
    final taskBlockRegex = RegExp(r'```task\s*([\s\S]*?)```', multiLine: true);
    final match = taskBlockRegex.firstMatch(content);
    if (match != null) {
      final block = match.group(1) ?? '';
      String name = '';
      String schedule = '*/30 * * * *';
      String actionType = 'gateway_check';
      String command = '';

      for (final line in block.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('名称:')) {
          name = trimmed.substring(3).trim();
        } else if (trimmed.startsWith('周期:')) {
          schedule = trimmed.substring(3).trim();
        } else if (trimmed.startsWith('类型:')) {
          final t = trimmed.substring(3).trim();
          if (t.contains('gateway') || t.contains('网关')) {
            actionType = 'gateway_check';
          } else if (t.contains('skills') || t.contains('插件')) {
            actionType = 'skills_reload';
          } else if (t.contains('shell') || t.contains('命令')) {
            actionType = 'shell_cmd';
          } else {
            actionType = t;
          }
        } else if (trimmed.startsWith('命令:')) {
          command = trimmed.substring(3).trim();
        }
      }

      if (name.isNotEmpty) {
        final newTask = ScheduledTaskModel(
          id: 'task_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          schedule: schedule.isNotEmpty ? schedule : '*/30 * * * *',
          actionType: actionType,
          command: command,
          isEnabled: true,
        );
        await addTask(newTask);
      }
    }
  }

  // ==================== 微信通道管理 ====================

  /// 启动微信通道
  Future<void> startWechatChannel() async {
    final savedAuth = await _dbService.loadWechatToken();
    final savedToken = savedAuth['botToken'];
    final savedName = savedAuth['botName'] ?? '微信助手';
    if (savedToken != null && savedToken.isNotEmpty) {
      await WechatChannelService.instance.restoreSession(
        botToken: savedToken,
        botName: savedName,
        autoReply: _config.wechatAutoReply,
        onMessage: _handleInboundWechatMessage,
      );
    } else {
      await WechatChannelService.instance.start(
        autoReply: _config.wechatAutoReply,
        onMessage: _handleInboundWechatMessage,
      );
    }
    notifyListeners();
  }

  /// 刷新获取全新微信登录二维码（强制重置凭证并重新扫码）
  Future<void> refreshWechatQrCode() async {
    await _dbService.clearWechatToken();
    await WechatChannelService.instance.refreshQrCode();
    notifyListeners();
  }

  /// 停止微信通道并清除持久化凭证
  Future<void> stopWechatChannel() async {
    await WechatChannelService.instance.stop();
    await _dbService.clearWechatToken();
    notifyListeners();
  }

  /// 切换微信通道启用开关
  Future<void> toggleWechatChannel(bool enabled) async {
    _config.wechatChannelEnabled = enabled;
    await _dbService.saveConfig(_config);
    if (enabled) {
      await startWechatChannel();
    } else {
      await stopWechatChannel();
    }
    notifyListeners();
  }

  /// 切换微信自动回复功能开关
  Future<void> setWechatAutoReply(bool enabled) async {
    _config.wechatAutoReply = enabled;
    await _dbService.saveConfig(_config);
    WechatChannelService.instance.setAutoReply(enabled);
    notifyListeners();
  }

  /// 处理微信入站消息
  Future<String?> _handleInboundWechatMessage(
    String senderId,
    String senderName,
    String messageText,
  ) async {
    final sessionId = 'wx_$senderId';
    var session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == sessionId,
      orElse: () => null,
    );

    if (session == null) {
      session = ChatSessionModel(
        id: sessionId,
        title: '$senderName (微信)',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        channel: 'wechat',
        unreadCount: 0,
      );
      await _dbService.insertSession(session);
      _sessions.insert(0, session);
    }

    final userMsg = ChatMessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: messageText,
      timestamp: DateTime.now(),
    );
    session.messages.add(userMsg);
    session.updatedAt = DateTime.now();

    // 如果未处于该会话，未读计数加一
    if (_activeSessionId != session.id) {
      session.unreadCount++;
    }
    await _dbService.saveMessage(session.id, userMsg);
    await _dbService.updateSession(session);
    notifyListeners();

    // 若开启自动回复，调用模型生成文本回复
    if (!_config.wechatAutoReply) {
      return null;
    }

    try {
      final replyText = await _agentService.sendMessage(
        config: _config,
        history: session.messages,
        activeSkills: _skills,
        userPrompt: messageText,
      );

      if (replyText.isNotEmpty) {
        final assistantMsg = ChatMessageModel(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}_reply',
          role: MessageRole.assistant,
          content: replyText,
          timestamp: DateTime.now(),
        );
        session.messages.add(assistantMsg);
        session.updatedAt = DateTime.now();
        await _dbService.saveMessage(session.id, assistantMsg);
        await _dbService.updateSession(session);
        notifyListeners();
        return replyText;
      }
    } catch (_) {}

    return null;
  }
}

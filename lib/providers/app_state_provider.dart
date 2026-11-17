import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../models/gateway_config.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../models/skill_model.dart';
import '../models/scheduled_task_model.dart';
import '../models/task_log_model.dart';
import '../services/database_service.dart';
import '../services/skill_service.dart';
import '../services/agent_service.dart';
import '../services/cron_scheduler_service.dart';
import '../services/gateway_server.dart';
import '../services/tray_service.dart';
import '../theme/openclaw_theme.dart';

/// 全局应用状态管理
class AppStateProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService.instance;
  final SkillService _skillService = SkillService();
  final AgentService _agentService = AgentService();
  final CronSchedulerService _cronService = CronSchedulerService.instance;
  late final GatewayServer _gatewayServer;

  int _currentTabIndex = 0;
  bool _isBusy = false;
  bool _isGatewayOnline = false;
  String _gatewayStatusMessage = '未启动';
  GatewayConfig _config = GatewayConfig.initial();
  List<SkillModel> _skills = [];
  List<ScheduledTaskModel> _tasks = [];
  List<TaskLogModel> _taskLogs = [];

  // 多会话管理
  List<ChatSessionModel> _sessions = [];
  String? _activeSessionId;

  String? _currentStreamSessionId;
  bool _isCurrentAborted = false;
  WebSocket? _wsClient;

  AppStateProvider() {
    _gatewayServer = GatewayServer(
      skillService: _skillService,
      agentService: _agentService,
    );
  }

  int get currentTabIndex => _currentTabIndex;
  bool get isBusy => _isBusy;
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
    OpenClawTheme.isDark = isDark;
    await _syncWindowTheme(isDark);

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

    _updateTrayMenu();
    notifyListeners();
  }

  // ==================== 主题切换 ====================

  /// 切换明暗主题
  Future<void> toggleTheme() async {
    _config.themeMode = isDarkTheme ? 'light' : 'dark';
    final isDark = _config.themeMode == 'dark';
    OpenClawTheme.isDark = isDark;
    await _syncWindowTheme(isDark);
    await _dbService.saveConfig(_config);
    notifyListeners();
  }

  // ==================== 会话管理 ====================

  /// 创建新会话，并自动切换到对话标签页
  Future<void> createNewSession() async {
    final now = DateTime.now();
    final session = ChatSessionModel(
      id: 'session_${now.millisecondsSinceEpoch}',
      title: '新会话',
      createdAt: now,
      updatedAt: now,
    );
    await _dbService.insertSession(session);
    _sessions.insert(0, session);
    _activeSessionId = session.id;
    _currentTabIndex = 0; // 保持在对话页
    notifyListeners();
  }

  /// 切换到指定会话
  void switchSession(String sessionId) {
    if (_activeSessionId == sessionId) {
      return;
    }
    _activeSessionId = sessionId;
    _currentTabIndex = 0;
    notifyListeners();
  }

  /// 删除指定会话，优先选中最靠近的相邻会话
  Future<void> deleteSession(String sessionId) async {
    final deleteIndex = _sessions.indexWhere((s) => s.id == sessionId);
    await _dbService.deleteSession(sessionId);
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

  /// 删除指定计划任务
  Future<void> removeTask(String taskId) async {
    await _dbService.deleteTask(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    _syncCronScheduler();
    notifyListeners();
  }

  // ==================== 配置保存与更新 ====================

  /// 保存并更新设置
  Future<void> updateConfig(GatewayConfig newConfig) async {
    final portChanged = _config.gatewayPort != newConfig.gatewayPort;
    final autoStartChanged = _config.autoStartGateway != newConfig.autoStartGateway;

    _config = newConfig;
    final isDark = _config.themeMode == 'dark';
    OpenClawTheme.isDark = isDark;
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

  /// 发送用户消息并进行 WebSocket 实时流式交互
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isBusy || _activeSessionId == null) {
      return;
    }

    final session = _sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == _activeSessionId,
      orElse: () => null,
    );
    if (session == null) {
      return;
    }

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentStreamSessionId = msgId;
    _isCurrentAborted = false;

    final userMessage = ChatMessageModel(
      id: msgId,
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
      status: MessageStatus.done,
    );
    session.messages.add(userMessage);
    await _dbService.saveMessage(_activeSessionId!, userMessage);

    // 自动从首条用户消息更新会话标题
    _autoUpdateSessionTitle(session, trimmed);

    final assistantMsgId = '${msgId}_bot';
    final assistantMessage = ChatMessageModel(
      id: assistantMsgId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.streaming,
    );
    session.messages.add(assistantMessage);

    _isBusy = true;
    notifyListeners();

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
        await _sendViaDirectStream(msgId, trimmed, assistantMessage);
      }
    }

    assistantMessage.status = assistantMessage.status == MessageStatus.streaming
        ? MessageStatus.done
        : assistantMessage.status;
    await _dbService.saveMessage(_activeSessionId!, assistantMessage);

    // 解析 AI 回复中的定时任务注册指令
    await _tryRegisterTaskFromAiResponse(assistantMessage.content);

    // 更新会话活跃时间
    session.updatedAt = DateTime.now();
    await _dbService.updateSession(session);

    // 刷新会话排序
    _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    _isBusy = false;
    _currentStreamSessionId = null;
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
    ChatMessageModel assistantMessage,
  ) async {
    final activeSkills = _skills.where((s) => s.isEnabled).toList();
    final validHistory = messages
        .where((m) => m.id != assistantMessage.id && m.status == MessageStatus.done)
        .toList();
    final contentBuffer = StringBuffer();

    await for (final event in _agentService.sendMessageStream(
      config: _config,
      history: validHistory,
      activeSkills: activeSkills,
      userPrompt: prompt,
      isAborted: () => _isCurrentAborted,
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

  /// 中止当前正在进行的生成
  void abortCurrentGeneration() {
    if (!_isBusy) {
      return;
    }

    _isCurrentAborted = true;

    if (_wsClient != null && _currentStreamSessionId != null) {
      try {
        _wsClient!.add(jsonEncode({
          'type': 'abort',
          'id': _currentStreamSessionId,
        }));
      } catch (_) {}
    }

    notifyListeners();
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
}

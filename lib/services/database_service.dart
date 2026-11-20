import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/chat_session_model.dart';
import '../models/chat_message_model.dart';
import '../models/scheduled_task_model.dart';
import '../models/task_log_model.dart';
import '../models/gateway_config.dart';
import '../models/claude_profile.dart';
import '../models/claude_process_instance.dart';
import '../models/checkpoint_model.dart';
import '../utils/path_utils.dart';

/// 基于 SQLite 的本地数据存储与持久化服务
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;

  /// 获取或初始化数据库实例
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  /// 初始化 SQLite 数据库连接及数据表
  Future<Database> _initDatabase() async {
    // 桌面端初始化 FFI 数据库工厂
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;

    final dbPath = '${PathUtils.agentHubRootDir}/agenthub.db';
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          // 会话表
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              unread_count INTEGER NOT NULL DEFAULT 0,
              channel TEXT NOT NULL DEFAULT 'internal',
              deleted_at INTEGER,
              profile_id TEXT,
              tokens_used INTEGER NOT NULL DEFAULT 0,
              session_mode TEXT NOT NULL DEFAULT 'chat',
              work_dir TEXT
            )
          ''');

          // 会话消息表
          await db.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              status TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
            )
          ''');

          // 定时计划任务表
          await db.execute('''
            CREATE TABLE scheduled_tasks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              schedule TEXT NOT NULL,
              tag TEXT,
              action_type TEXT NOT NULL,
              command TEXT,
              is_enabled INTEGER NOT NULL DEFAULT 1,
              next_run INTEGER,
              last_run INTEGER,
              last_status TEXT
            )
          ''');

          // 任务运行历史日志表
          await db.execute('''
            CREATE TABLE task_logs (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              task_name TEXT NOT NULL,
              executed_at INTEGER NOT NULL,
              duration_ms INTEGER NOT NULL,
              is_success INTEGER NOT NULL,
              output TEXT
            )
          ''');

          // 全局配置键值表
          await db.execute('''
            CREATE TABLE configs (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');

          // Claude Profile 账号配置表
          await db.execute('''
            CREATE TABLE claude_profiles (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              remark TEXT,
              website_url TEXT,
              auth_type TEXT NOT NULL DEFAULT 'oauth',
              api_key_ref TEXT,
              api_base_url TEXT,
              api_format TEXT,
              auth_field TEXT,
              sonnet_mapping TEXT,
              opus_mapping TEXT,
              fable_mapping TEXT,
              haiku_mapping TEXT,
              default_fallback_model TEXT,
              user_agent TEXT,
              hide_co_authored_by INTEGER NOT NULL DEFAULT 0,
              disable_non_essential_traffic INTEGER NOT NULL DEFAULT 1,
              disable_auto_update INTEGER NOT NULL DEFAULT 0,
              enable_tool_search INTEGER NOT NULL DEFAULT 0,
              max_thinking INTEGER NOT NULL DEFAULT 0,
              teammates_mode INTEGER NOT NULL DEFAULT 0,
              config_dir TEXT NOT NULL,
              extra_settings_json TEXT,
              created_at INTEGER NOT NULL,
              last_used_at INTEGER NOT NULL
            )
          ''');

          // Claude 进程实例表
          await db.execute('''
            CREATE TABLE claude_instances (
              id TEXT PRIMARY KEY,
              profile_id TEXT NOT NULL,
              work_dir TEXT NOT NULL,
              session_id TEXT,
              status TEXT NOT NULL DEFAULT 'idle',
              current_task TEXT,
              started_at INTEGER NOT NULL,
              last_output TEXT,
              deleted_at INTEGER,
              FOREIGN KEY (profile_id) REFERENCES claude_profiles (id)
            )
          ''');
        },
      ),
    );

    // 检查并升级已有表结构与新增表
    try {
      final sessionInfo = await db.rawQuery('PRAGMA table_info(sessions)');
      final sessionColumns = sessionInfo.map((r) => r['name']?.toString()).toSet();
      if (!sessionColumns.contains('unread_count')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN unread_count INTEGER NOT NULL DEFAULT 0');
      }
      if (!sessionColumns.contains('channel')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN channel TEXT NOT NULL DEFAULT "internal"');
      }
      if (!sessionColumns.contains('deleted_at')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN deleted_at INTEGER');
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS claude_profiles (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          remark TEXT,
          website_url TEXT,
          auth_type TEXT NOT NULL DEFAULT 'oauth',
          api_key_ref TEXT,
          api_base_url TEXT,
          api_format TEXT,
          auth_field TEXT,
          sonnet_mapping TEXT,
          opus_mapping TEXT,
          fable_mapping TEXT,
          haiku_mapping TEXT,
          default_fallback_model TEXT,
          user_agent TEXT,
          hide_co_authored_by INTEGER NOT NULL DEFAULT 0,
          disable_non_essential_traffic INTEGER NOT NULL DEFAULT 1,
          disable_auto_update INTEGER NOT NULL DEFAULT 0,
          enable_tool_search INTEGER NOT NULL DEFAULT 0,
          max_thinking INTEGER NOT NULL DEFAULT 0,
          teammates_mode INTEGER NOT NULL DEFAULT 0,
          config_dir TEXT NOT NULL,
          extra_settings_json TEXT,
          created_at INTEGER NOT NULL,
          last_used_at INTEGER NOT NULL
        )
      ''');

      final profileInfo = await db.rawQuery('PRAGMA table_info(claude_profiles)');
      final profileColumns = profileInfo.map((r) => r['name']?.toString()).toSet();
      final columnsToAdd = {
        'remark': 'TEXT',
        'website_url': 'TEXT',
        'api_base_url': 'TEXT',
        'api_format': 'TEXT',
        'auth_field': 'TEXT',
        'sonnet_mapping': 'TEXT',
        'opus_mapping': 'TEXT',
        'fable_mapping': 'TEXT',
        'haiku_mapping': 'TEXT',
        'default_fallback_model': 'TEXT',
        'user_agent': 'TEXT',
        'hide_co_authored_by': 'INTEGER NOT NULL DEFAULT 0',
        'disable_non_essential_traffic': 'INTEGER NOT NULL DEFAULT 1',
        'disable_auto_update': 'INTEGER NOT NULL DEFAULT 0',
        'enable_tool_search': 'INTEGER NOT NULL DEFAULT 0',
        'max_thinking': 'INTEGER NOT NULL DEFAULT 0',
        'teammates_mode': 'INTEGER NOT NULL DEFAULT 0',
        'extra_settings_json': 'TEXT',
      };
      for (final entry in columnsToAdd.entries) {
        if (!profileColumns.contains(entry.key)) {
          await db.execute('ALTER TABLE claude_profiles ADD COLUMN ${entry.key} ${entry.value}');
        }
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS claude_instances (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL,
          work_dir TEXT NOT NULL,
          session_id TEXT,
          status TEXT NOT NULL DEFAULT 'idle',
          current_task TEXT,
          started_at INTEGER NOT NULL,
          last_output TEXT,
          deleted_at INTEGER,
          FOREIGN KEY (profile_id) REFERENCES claude_profiles (id)
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('ALTER TABLE sessions ADD COLUMN profile_id TEXT;');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sessions ADD COLUMN tokens_used INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE sessions ADD COLUMN session_mode TEXT NOT NULL DEFAULT 'chat';");
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE sessions ADD COLUMN work_dir TEXT;');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS checkpoints (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          work_dir TEXT NOT NULL,
          changed_files TEXT NOT NULL,
          diff_summary TEXT NOT NULL,
          diff_content TEXT,
          backup_dir TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          is_rolled_back INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
        )
      ''');
    } catch (_) {}

    return db;
  }

  // ==================== 会话与消息管理 ====================

  /// 获取所有活跃会话列表（未被软删除，按最后更新时间倒序排列）
  Future<List<ChatSessionModel>> loadSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> sessionRows = await db.query(
      'sessions',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    return _parseSessionsWithMessages(db, sessionRows);
  }

  /// 获取所有已被软删除的会话列表（回收站列表）
  Future<List<ChatSessionModel>> loadDeletedSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> sessionRows = await db.query(
      'sessions',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );

    return _parseSessionsWithMessages(db, sessionRows);
  }

  /// 内部方法：从会话行解析完整会话对象及消息
  Future<List<ChatSessionModel>> _parseSessionsWithMessages(
    Database db,
    List<Map<String, dynamic>> sessionRows,
  ) async {
    final List<ChatSessionModel> sessions = [];
    for (final row in sessionRows) {
      final sessionId = row['id'] as String;
      final List<Map<String, dynamic>> messageRows = await db.query(
        'messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC',
      );

      final ckptList = await getCheckpointsBySessionId(sessionId);
      final ckptMap = {for (final c in ckptList) c.messageId: c};

      final messages = messageRows.map((m) {
        final msgId = m['id'] as String;
        final ckpt = ckptMap[msgId];
        return ChatMessageModel(
          id: msgId,
          role: MessageRole.values.firstWhere(
            (r) => r.name == m['role'],
            orElse: () => MessageRole.user,
          ),
          content: m['content'] as String,
          status: MessageStatus.values.firstWhere(
            (s) => s.name == m['status'],
            orElse: () => MessageStatus.done,
          ),
          timestamp: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
          checkpointId: ckpt?.id,
          checkpoint: ckpt,
        );
      }).toList();

      sessions.add(ChatSessionModel(
        id: sessionId,
        title: row['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        messages: messages,
        unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
        channel: row['channel'] as String? ?? 'internal',
        deletedAt: row['deleted_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int)
            : null,
        profileId: row['profile_id'] as String?,
        tokensUsed: (row['tokens_used'] as num?)?.toInt() ?? 0,
        sessionMode: row['session_mode'] as String? ?? 'chat',
        workDir: row['work_dir'] as String?,
      ));
    }

    return sessions;
  }

  /// 创建新会话
  Future<void> insertSession(ChatSessionModel session) async {
    final db = await database;
    await db.insert(
      'sessions',
      {
        'id': session.id,
        'title': session.title,
        'created_at': session.createdAt.millisecondsSinceEpoch,
        'updated_at': session.updatedAt.millisecondsSinceEpoch,
        'unread_count': session.unreadCount,
        'channel': session.channel,
        'deleted_at': session.deletedAt?.millisecondsSinceEpoch,
        'profile_id': session.profileId,
        'tokens_used': session.tokensUsed,
        'session_mode': session.sessionMode,
        'work_dir': session.workDir,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新会话标题、更新时间与未读数
  Future<void> updateSession(ChatSessionModel session) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'title': session.title,
        'updated_at': session.updatedAt.millisecondsSinceEpoch,
        'unread_count': session.unreadCount,
        'channel': session.channel,
        'deleted_at': session.deletedAt?.millisecondsSinceEpoch,
        'profile_id': session.profileId,
        'tokens_used': session.tokensUsed,
        'session_mode': session.sessionMode,
        'work_dir': session.workDir,
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  /// 软删除会话（标记删除时间戳）
  Future<void> softDeleteSession(String sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 恢复软删除的会话
  Future<void> restoreSession(String sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 物理删除超过 7 天的已软删除会话及关联消息
  Future<int> purgeExpiredSessions() async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final expiredRows = await db.query(
      'sessions',
      columns: ['id'],
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [sevenDaysAgo],
    );

    if (expiredRows.isEmpty) return 0;

    final ids = expiredRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');

    await db.delete('messages', where: 'session_id IN ($placeholders)', whereArgs: ids);
    final count = await db.delete('sessions', where: 'id IN ($placeholders)', whereArgs: ids);
    return count;
  }

  /// 将会话标记为已读
  Future<void> markSessionAsRead(String sessionId) async {
    final db = await database;
    await db.update(
      'sessions',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 删除指定会话及其全部消息
  Future<void> deleteSession(String sessionId) async {
    final db = await database;
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// 插入或更新单条消息
  Future<void> saveMessage(String sessionId, ChatMessageModel message) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'session_id': sessionId,
        'role': message.role.name,
        'content': message.content,
        'status': message.status.name,
        'created_at': message.timestamp.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 联动更新会话活跃时间
    await db.update(
      'sessions',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 删除指定单条消息
  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  /// 清空指定会话的消息
  Future<void> clearSessionMessages(String sessionId) async {
    final db = await database;
    await db.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  // ==================== 定时计划任务管理 ====================

  /// 读取所有计划任务
  Future<List<ScheduledTaskModel>> loadTasks() async {
    final db = await database;
    final List<Map<String, dynamic>> rows = await db.query('scheduled_tasks');
    // 无任务时返回空列表，不再插入默认任务
    if (rows.isEmpty) {
      return [];
    }

    return rows.map((r) {
      return ScheduledTaskModel(
        id: r['id'] as String,
        name: r['name'] as String,
        schedule: r['schedule'] as String,
        tag: r['tag'] as String?,
        actionType: r['action_type'] as String? ?? 'gateway_check',
        command: r['command'] as String? ?? '',
        isEnabled: (r['is_enabled'] as int) == 1,
        nextRun: r['next_run'] != null
            ? DateTime.fromMillisecondsSinceEpoch(r['next_run'] as int)
            : null,
        lastRun: r['last_run'] != null
            ? DateTime.fromMillisecondsSinceEpoch(r['last_run'] as int)
            : null,
        lastStatus: r['last_status'] as String?,
      );
    }).toList();
  }

  /// 插入或更新计划任务
  Future<void> saveTask(ScheduledTaskModel task) async {
    final db = await database;
    await db.insert(
      'scheduled_tasks',
      {
        'id': task.id,
        'name': task.name,
        'schedule': task.schedule,
        'tag': task.tag,
        'action_type': task.actionType,
        'command': task.command,
        'is_enabled': task.isEnabled ? 1 : 0,
        'next_run': task.nextRun?.millisecondsSinceEpoch,
        'last_run': task.lastRun?.millisecondsSinceEpoch,
        'last_status': task.lastStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除指定计划任务
  Future<void> deleteTask(String taskId) async {
    final db = await database;
    await db.delete('scheduled_tasks', where: 'id = ?', whereArgs: [taskId]);
  }

  // ==================== 任务运行日志管理 ====================

  /// 读取任务运行历史记录（最新的排前面）
  Future<List<TaskLogModel>> loadTaskLogs({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> rows = await db.query(
      'task_logs',
      orderBy: 'executed_at DESC',
      limit: limit,
    );
    return rows.map((r) {
      return TaskLogModel(
        id: r['id'] as String,
        taskId: r['task_id'] as String,
        taskName: r['task_name'] as String,
        executedAt: DateTime.fromMillisecondsSinceEpoch(r['executed_at'] as int),
        durationMs: r['duration_ms'] as int,
        isSuccess: (r['is_success'] as int) == 1,
        output: r['output'] as String? ?? '',
      );
    }).toList();
  }

  /// 插入一条任务执行历史日志
  Future<void> insertTaskLog(TaskLogModel log) async {
    final db = await database;
    await db.insert(
      'task_logs',
      {
        'id': log.id,
        'task_id': log.taskId,
        'task_name': log.taskName,
        'executed_at': log.executedAt.millisecondsSinceEpoch,
        'duration_ms': log.durationMs,
        'is_success': log.isSuccess ? 1 : 0,
        'output': log.output,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 检索包含特定关键字的消息记录与会话信息
  Future<List<Map<String, dynamic>>> searchMessages(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final db = await database;
    final results = await db.rawQuery('''
      SELECT m.id, m.session_id, m.role, m.content, m.created_at, s.title as session_title
      FROM messages m
      JOIN sessions s ON m.session_id = s.id
      WHERE m.content LIKE ?
      ORDER BY m.created_at DESC
      LIMIT 50
    ''', ['%$trimmed%']);

    return results;
  }

  /// 清空会话与全部消息记录
  Future<void> resetAllSessions() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('sessions');
  }

  /// 清空任务运行历史日志
  Future<void> clearTaskLogs({String? taskId}) async {
    final db = await database;
    if (taskId != null && taskId.isNotEmpty) {
      await db.delete('task_logs', where: 'task_id = ?', whereArgs: [taskId]);
    } else {
      await db.delete('task_logs');
    }
  }

  // ==================== 配置读取与存储 ====================

  /// 读取配置
  Future<GatewayConfig> loadConfig() async {
    final db = await database;
    final rows = await db.query('configs');
    final Map<String, String> map = {};
    for (final r in rows) {
      map[r['key'] as String] = r['value'] as String;
    }

    if (map.isEmpty) {
      // 检查是否有历史 json 配置做初次兼容读取
      final legacyConfigFile = File('${PathUtils.agentHubRootDir}/config.json');
      if (legacyConfigFile.existsSync()) {
        try {
          final content = await legacyConfigFile.readAsString();
          final jsonMap = jsonDecode(content) as Map<String, dynamic>;
          final config = GatewayConfig.fromJson(jsonMap);
          await saveConfig(config);
          return config;
        } catch (_) {}
      }
      return GatewayConfig.initial();
    }

    return GatewayConfig(
      gatewayPort: int.tryParse(map['gatewayPort'] ?? '18789') ?? 18789,
      autoStartGateway: map['autoStartGateway'] != 'false',
      apiBaseUrl: map['apiBaseUrl'] ?? '',
      apiKey: map['apiKey'] ?? '',
      modelName: map['modelName'] ?? '',
      customSkillsPath: map['customSkillsPath'] ?? '',
      minimizeToTrayOnClose: map['minimizeToTrayOnClose'] != 'false',
      themeMode: map['themeMode'] ?? 'light',
      httpProxy: map['httpProxy'] ?? '',
      temperature: double.tryParse(map['temperature'] ?? '0.7') ?? 0.7,
      topP: double.tryParse(map['topP'] ?? '0.9') ?? 0.9,
      wechatChannelEnabled: map['wechatChannelEnabled'] == 'true',
      wechatAutoReply: map['wechatAutoReply'] == 'true',
    );
  }

  /// 保存配置
  Future<void> saveConfig(GatewayConfig config) async {
    final db = await database;
    final entries = {
      'gatewayPort': config.gatewayPort.toString(),
      'autoStartGateway': config.autoStartGateway.toString(),
      'apiBaseUrl': config.apiBaseUrl,
      'apiKey': config.apiKey,
      'modelName': config.modelName,
      'customSkillsPath': config.customSkillsPath,
      'minimizeToTrayOnClose': config.minimizeToTrayOnClose.toString(),
      'themeMode': config.themeMode,
      'httpProxy': config.httpProxy,
      'temperature': config.temperature.toString(),
      'topP': config.topP.toString(),
      'wechatChannelEnabled': config.wechatChannelEnabled.toString(),
      'wechatAutoReply': config.wechatAutoReply.toString(),
    };

    final batch = db.batch();
    entries.forEach((k, v) {
      batch.insert(
        'configs',
        {'key': k, 'value': v},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  /// 保存微信通道凭证
  Future<void> saveWechatToken(String botToken, String botName) async {
    final db = await database;
    final batch = db.batch();
    batch.insert('configs', {'key': 'wechat_bot_token', 'value': botToken}, conflictAlgorithm: ConflictAlgorithm.replace);
    batch.insert('configs', {'key': 'wechat_bot_name', 'value': botName}, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  /// 读取持久化的微信通道凭证
  Future<Map<String, String?>> loadWechatToken() async {
    final db = await database;
    final rows = await db.query(
      'configs',
      where: 'key IN (?, ?)',
      whereArgs: ['wechat_bot_token', 'wechat_bot_name'],
    );
    String? token;
    String? name;
    for (final r in rows) {
      if (r['key'] == 'wechat_bot_token') token = r['value']?.toString();
      if (r['key'] == 'wechat_bot_name') name = r['value']?.toString();
    }
    return {'botToken': token, 'botName': name};
  }

  /// 清除微信通道持久化凭证
  Future<void> clearWechatToken() async {
    final db = await database;
    await db.delete('configs', where: 'key IN (?, ?)', whereArgs: ['wechat_bot_token', 'wechat_bot_name']);
  }

  // ==================== Claude Profile 管理 ====================

  /// 读取所有 Profile 账号
  Future<List<ClaudeProfile>> loadProfiles() async {
    final db = await database;
    final rows = await db.query('claude_profiles', orderBy: 'last_used_at DESC');
    return rows.map((r) => ClaudeProfile.fromMap(r)).toList();
  }

  /// 插入或更新 Profile
  Future<void> saveProfile(ClaudeProfile profile) async {
    final db = await database;
    await db.insert(
      'claude_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除指定 Profile
  Future<void> deleteProfile(String profileId) async {
    final db = await database;
    await db.delete('claude_profiles', where: 'id = ?', whereArgs: [profileId]);
  }

  // ==================== Claude 实例管理 ====================

  /// 读取所有未被软删除的实例记录
  Future<List<ClaudeProcessInstance>> loadInstances() async {
    final db = await database;
    final rows = await db.query(
      'claude_instances',
      where: 'deleted_at IS NULL',
      orderBy: 'started_at DESC',
    );
    return rows.map((r) => ClaudeProcessInstance.fromMap(r)).toList();
  }

  /// 保存或更新实例记录
  Future<void> saveInstance(ClaudeProcessInstance instance) async {
    final db = await database;
    await db.insert(
      'claude_instances',
      instance.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 软删除实例记录
  Future<void> softDeleteInstance(String instanceId) async {
    final db = await database;
    await db.update(
      'claude_instances',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [instanceId],
    );
  }

  /// 物理删除超过 7 天的实例记录
  Future<int> purgeExpiredInstances() async {
    final db = await database;
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    return await db.delete(
      'claude_instances',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  // ==================== 工作区 Checkpoint 快照管理 ====================

  /// 保存文件快照 Checkpoint
  Future<void> saveCheckpoint(CheckpointModel checkpoint) async {
    final db = await database;
    await db.insert(
      'checkpoints',
      checkpoint.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新 Checkpoint（例如标记已回退）
  Future<void> updateCheckpoint(CheckpointModel checkpoint) async {
    final db = await database;
    await db.update(
      'checkpoints',
      checkpoint.toMap(),
      where: 'id = ?',
      whereArgs: [checkpoint.id],
    );
  }

  /// 根据消息 ID 获取对应的 Checkpoint
  Future<CheckpointModel?> getCheckpointByMessageId(String messageId) async {
    final db = await database;
    final rows = await db.query(
      'checkpoints',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CheckpointModel.fromMap(rows.first);
  }

  /// 根据会话 ID 获取所有历史 Checkpoint 列表
  Future<List<CheckpointModel>> getCheckpointsBySessionId(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'checkpoints',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => CheckpointModel.fromMap(r)).toList();
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/chat_session_model.dart';
import '../models/chat_message_model.dart';
import '../models/scheduled_task_model.dart';
import '../models/task_log_model.dart';
import '../models/gateway_config.dart';
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
        version: 1,
        onCreate: (db, version) async {
          // 会话表
          await db.execute('''
            CREATE TABLE sessions (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              unread_count INTEGER NOT NULL DEFAULT 0,
              channel TEXT NOT NULL DEFAULT 'internal'
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
        },
      ),
    );

    // 检查并升级 sessions 表结构
    try {
      final info = await db.rawQuery('PRAGMA table_info(sessions)');
      final columns = info.map((r) => r['name']?.toString()).toSet();
      if (!columns.contains('unread_count')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN unread_count INTEGER NOT NULL DEFAULT 0');
      }
      if (!columns.contains('channel')) {
        await db.execute('ALTER TABLE sessions ADD COLUMN channel TEXT NOT NULL DEFAULT "internal"');
      }
    } catch (_) {}

    return db;
  }

  // ==================== 会话与消息管理 ====================

  /// 获取所有真实会话列表（按最后更新时间倒序排列）
  Future<List<ChatSessionModel>> loadSessions() async {
    final db = await database;
    final List<Map<String, dynamic>> sessionRows = await db.query(
      'sessions',
      orderBy: 'updated_at DESC',
    );

    final List<ChatSessionModel> sessions = [];
    for (final row in sessionRows) {
      final sessionId = row['id'] as String;
      final List<Map<String, dynamic>> messageRows = await db.query(
        'messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC',
      );

      final messages = messageRows.map((m) {
        return ChatMessageModel(
          id: m['id'] as String,
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
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
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
}

# Claude Code 管理器 + 多任务 AI 编程工作台 - 技术规划文档

## 一、项目定位

在现有 AgentHub 基础上，新增 **Claude Code 进程管理** 模块。核心思路：

- Claude Code CLI 是真正的执行引擎
- Flutter 负责管理、调度、展示 Claude Code 的工作过程
- 支持多个 Claude Code 实例同时运行，每个实例独立工作目录、账号、会话

---

## 二、整体架构

```
┌─────────────────────────────────────────────────┐
│                  Flutter UI 层                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ 环境管理  │ │ Profile  │ │ 多任务工作台      │  │
│  │ 页面     │ │ 管理页面  │ │ (进程面板)        │  │
│  └────┬─────┘ └────┬─────┘ └────────┬─────────┘  │
│       │            │                │             │
│  ┌────┴────────────┴────────────────┴──────────┐  │
│  │          AppStateProvider (扩展)             │  │
│  └────┬────────────┬────────────────┬──────────┘  │
├───────┼────────────┼────────────────┼─────────────┤
│       │   Service 层                │             │
│  ┌────┴─────┐ ┌────┴─────┐ ┌───────┴──────────┐  │
│  │ Claude   │ │ Profile  │ │ ClaudeProcess    │  │
│  │ Env      │ │ Service  │ │ Manager          │  │
│  │ Service  │ │          │ │ (多实例调度)      │  │
│  └────┬─────┘ └────┬─────┘ └───────┬──────────┘  │
│       │            │               │              │
│  ┌────┴────────────┴───────────────┴──────────┐   │
│  │       Credential Service                    │   │
│  │  (flutter_secure_storage / Keychain)        │   │
│  └─────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────┤
│                    OS 进程层                         │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐               │
│  │ claude  │ │ claude  │ │ claude  │  ...           │
│  │ -p      │ │ -p      │ │ -p      │               │
│  │ 实例 1  │ │ 实例 2  │ │ 实例 3  │               │
│  └─────────┘ └─────────┘ └─────────┘               │
└─────────────────────────────────────────────────────┘
```

---

## 三、模块拆解

### 3.1 Claude 环境检测服务 (`claude_env_service.dart`)

负责检测本机 Claude Code 安装状态。

**功能清单：**

| 功能 | 实现方式 |
|------|----------|
| 检测是否安装 | `which claude` / `where claude` |
| 获取版本号 | `claude --version` 解析 stdout |
| 获取可执行文件路径 | `which claude` 返回绝对路径 |
| 未安装时引导安装 | 展示安装命令 `npm install -g @anthropic-ai/claude-code` |

**数据模型：**

```dart
/// Claude Code 环境信息
class ClaudeEnvInfo {
  final bool isInstalled;
  final String? version;
  final String? executablePath;
  final String? nodePath;
  final String configDir; // ~/.claude

  const ClaudeEnvInfo({
    required this.isInstalled,
    this.version,
    this.executablePath,
    this.nodePath,
    this.configDir = '',
  });
}
```

**核心方法：**

```dart
class ClaudeEnvService {
  /// 检测 Claude Code 安装状态
  Future<ClaudeEnvInfo> detect();

  /// 获取版本号
  Future<String?> getVersion();

  /// 获取可执行文件完整路径
  Future<String?> getExecutablePath();

  /// 检查 Node.js 环境
  Future<bool> checkNodeInstalled();
}
```

---

### 3.2 Profile 管理服务 (`claude_profile_service.dart`)

借鉴 CCSwitch 的 Profile 机制，管理多个 Claude 账号和配置。

**Profile 数据模型：**

```dart
/// Claude Code 账号配置
class ClaudeProfile {
  final String id;
  String name;           // 显示名称，如 "工作账号"、"个人账号"
  String authType;       // oauth | api_key
  String? apiKeyRef;     // Keychain 中的引用 key，不存明文
  String configDir;      // 该 Profile 对应的配置目录
  String? model;         // 指定模型
  String? permissionMode;
  Map<String, String> envOverrides; // 额外环境变量
  DateTime createdAt;
  DateTime lastUsedAt;

  ClaudeProfile({...});
}
```

**存储策略：**

- Profile 元信息存 SQLite `claude_profiles` 表
- API Key 通过 `flutter_secure_storage` 存入 macOS Keychain / Windows Credential Manager
- 每个 Profile 在 `~/.agenthub/claude_profiles/<profile_id>/` 下维护独立的配置副本

**SQLite 表结构：**

```sql
CREATE TABLE claude_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  auth_type TEXT NOT NULL DEFAULT 'oauth',
  api_key_ref TEXT,
  config_dir TEXT NOT NULL,
  model TEXT,
  permission_mode TEXT,
  env_overrides TEXT,
  created_at INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);
```

**核心方法：**

```dart
class ClaudeProfileService {
  /// 获取所有 Profile
  Future<List<ClaudeProfile>> loadProfiles();

  /// 创建新 Profile
  Future<ClaudeProfile> createProfile({
    required String name,
    required String authType,
    String? apiKey,
  });

  /// 删除 Profile
  Future<void> deleteProfile(String profileId);

  /// 为指定 Profile 安全存储 API Key
  Future<void> saveApiKey(String profileId, String apiKey);

  /// 从系统安全存储读取 API Key
  Future<String?> loadApiKey(String profileId);

  /// 构建 Profile 对应的环境变量 Map
  Map<String, String> buildEnvForProfile(ClaudeProfile profile);
}
```

**环境变量隔离原理：**

每个 Profile 启动 Claude 进程时，通过设置环境变量实现隔离：

```dart
// 构建进程环境变量
Map<String, String> buildEnvForProfile(ClaudeProfile profile) {
  final env = Map<String, String>.from(Platform.environment);
  // 指向该 Profile 独立的配置目录
  env['CLAUDE_CONFIG_DIR'] = profile.configDir;
  // 如果有 API Key
  if (profile.authType == 'api_key') {
    final key = await loadApiKey(profile.id);
    if (key != null) env['ANTHROPIC_API_KEY'] = key;
  }
  // 指定模型
  if (profile.model != null) {
    env['ANTHROPIC_MODEL'] = profile.model!;
  }
  // 额外环境变量
  env.addAll(profile.envOverrides);
  return env;
}
```

---

### 3.3 安全凭证服务 (`credential_service.dart`)

统一管理敏感信息的存取，底层对接系统安全存储。

**依赖：** `flutter_secure_storage: ^11.0.0`

**macOS 配置要求：**

在 `macos/Runner/DebugProfile.entitlements` 和 `Release.entitlements` 中添加：

```xml
<key>com.apple.security.keychain-access-groups</key>
<array>
  <string>$(AppIdentifierPrefix)com.yuanzhijia.agenthub</string>
</array>
```

**核心方法：**

```dart
class CredentialService {
  static final CredentialService instance = CredentialService._();
  final _storage = const FlutterSecureStorage();

  /// 存储凭证
  Future<void> save(String key, String value);

  /// 读取凭证
  Future<String?> read(String key);

  /// 删除凭证
  Future<void> delete(String key);

  /// 存储 Profile 的 API Key
  Future<void> saveProfileApiKey(String profileId, String apiKey) {
    return save('claude_profile_$profileId', apiKey);
  }

  /// 读取 Profile 的 API Key
  Future<String?> readProfileApiKey(String profileId) {
    return read('claude_profile_$profileId');
  }
}
```

---

### 3.4 Claude 进程管理器 (`claude_process_manager.dart`)

核心模块，管理多个 Claude Code CLI 子进程的生命周期。

**进程实例数据模型：**

```dart
/// 单个 Claude Code 进程实例
class ClaudeProcessInstance {
  final String id;
  final String profileId;
  final String workDir;
  final String? sessionId;      // Claude 会话 ID，用于 --resume
  Process? process;
  ClaudeProcessStatus status;
  final StreamController<String> stdoutController;
  final StreamController<String> stderrController;
  DateTime startedAt;
  String? currentTask;          // 当前执行的任务描述

  ClaudeProcessInstance({...});
}

/// 进程状态
enum ClaudeProcessStatus {
  idle,       // 空闲
  running,    // 执行中
  streaming,  // 流式输出中
  error,      // 异常
  terminated, // 已终止
}
```

**SQLite 表结构：**

```sql
CREATE TABLE claude_instances (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  work_dir TEXT NOT NULL,
  session_id TEXT,
  status TEXT NOT NULL DEFAULT 'idle',
  current_task TEXT,
  started_at INTEGER NOT NULL,
  last_output TEXT,
  FOREIGN KEY (profile_id) REFERENCES claude_profiles (id)
);
```

**核心方法：**

```dart
class ClaudeProcessManager {
  final Map<String, ClaudeProcessInstance> _instances = {};

  /// 启动一个新的 Claude Code 进程
  Future<ClaudeProcessInstance> startInstance({
    required ClaudeProfile profile,
    required String workDir,
    String? resumeSessionId,
  });

  /// 向指定实例发送任务指令
  Future<void> sendTask({
    required String instanceId,
    required String prompt,
  });

  /// 以流式模式执行任务，返回实时输出流
  Stream<ClaudeStreamEvent> executeStreaming({
    required String instanceId,
    required String prompt,
  });

  /// 终止指定进程
  Future<void> killInstance(String instanceId);

  /// 获取所有活跃实例
  List<ClaudeProcessInstance> get activeInstances;

  /// 获取指定实例的输出流
  Stream<String> getOutputStream(String instanceId);
}
```

**进程启动核心逻辑：**

```dart
Future<ClaudeProcessInstance> startInstance({
  required ClaudeProfile profile,
  required String workDir,
  String? resumeSessionId,
}) async {
  final instanceId = 'inst_${DateTime.now().millisecondsSinceEpoch}';

  // 构建命令参数
  final args = <String>['-p', '--output-format', 'stream-json'];
  if (resumeSessionId != null) {
    args.addAll(['--resume', resumeSessionId]);
  }
  if (profile.model != null) {
    args.addAll(['--model', profile.model!]);
  }
  if (profile.permissionMode != null) {
    args.addAll(['--permission-mode', profile.permissionMode!]);
  }

  // 构建环境变量（含 CLAUDE_CONFIG_DIR 隔离）
  final env = await _profileService.buildEnvForProfile(profile);

  final instance = ClaudeProcessInstance(
    id: instanceId,
    profileId: profile.id,
    workDir: workDir,
    status: ClaudeProcessStatus.idle,
    startedAt: DateTime.now(),
  );

  _instances[instanceId] = instance;
  return instance;
}
```

**流式执行核心逻辑：**

```dart
Stream<ClaudeStreamEvent> executeStreaming({
  required String instanceId,
  required String prompt,
}) async* {
  final instance = _instances[instanceId];
  if (instance == null) return;

  instance.status = ClaudeProcessStatus.streaming;
  instance.currentTask = prompt;

  final execPath = await _envService.getExecutablePath();
  final args = ['-p', '--output-format', 'stream-json', prompt];
  final env = await _profileService.buildEnvForProfile(
    await _profileService.getProfile(instance.profileId),
  );

  final process = await Process.start(
    execPath!,
    args,
    workingDirectory: instance.workDir,
    environment: env,
  );
  instance.process = process;

  // 解析 NDJSON 流
  await for (final line in process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    final event = jsonDecode(line) as Map<String, dynamic>;
    yield ClaudeStreamEvent.fromJson(event);
  }

  final exitCode = await process.exitCode;
  instance.status = exitCode == 0
      ? ClaudeProcessStatus.idle
      : ClaudeProcessStatus.error;
  instance.process = null;
}
```

**流式事件模型：**

```dart
/// Claude Code stream-json 输出的事件
class ClaudeStreamEvent {
  final String type;     // init | assistant | tool_use | tool_result | result | error
  final String? content;
  final String? toolName;
  final String? toolInput;
  final String? toolOutput;
  final String? sessionId;
  final double? costUsd;
  final int? durationMs;

  ClaudeStreamEvent({...});

  factory ClaudeStreamEvent.fromJson(Map<String, dynamic> json) {
    return ClaudeStreamEvent(
      type: json['type'] ?? '',
      content: json['content']?.toString(),
      toolName: json['tool_name']?.toString(),
      toolInput: json['tool_input']?.toString(),
      toolOutput: json['tool_output']?.toString(),
      sessionId: json['session_id']?.toString(),
      costUsd: (json['cost_usd'] as num?)?.toDouble(),
      durationMs: (json['duration_ms'] as num?)?.toInt(),
    );
  }
}
```

---

## 四、会话软删除与定时清理

### 4.1 设计思路

会话删除采用**两阶段回收机制**：

1. 用户点击删除 -> 逻辑删除（标记 `deleted_at` 时间戳）
2. 7 天后 -> Cron 定时任务自动物理删除

逻辑删除期间，会话从列表中隐藏，但数据仍在数据库中，支持恢复。

### 4.2 数据库变更

`claude_instances` 表新增 `deleted_at` 字段：

```sql
ALTER TABLE claude_instances ADD COLUMN deleted_at INTEGER;
```

现有 `sessions` 表同样追加：

```sql
ALTER TABLE sessions ADD COLUMN deleted_at INTEGER;
```

### 4.3 会话删除服务逻辑

```dart
/// 逻辑删除会话（标记删除时间）
Future<void> softDeleteSession(String sessionId) async {
  final db = await database;
  await db.update(
    'sessions',
    {'deleted_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [sessionId],
  );
}

/// 恢复已逻辑删除的会话
Future<void> restoreSession(String sessionId) async {
  final db = await database;
  await db.update(
    'sessions',
    {'deleted_at': null},
    where: 'id = ?',
    whereArgs: [sessionId],
  );
}

/// 物理删除超过 7 天的已标记会话及其消息
Future<int> purgeExpiredSessions() async {
  final db = await database;
  final cutoff = DateTime.now()
      .subtract(const Duration(days: 7))
      .millisecondsSinceEpoch;

  // 查出待清理的会话 ID
  final rows = await db.query(
    'sessions',
    columns: ['id'],
    where: 'deleted_at IS NOT NULL AND deleted_at < ?',
    whereArgs: [cutoff],
  );

  if (rows.isEmpty) return 0;

  final ids = rows.map((r) => r['id'] as String).toList();
  final placeholders = List.filled(ids.length, '?').join(',');

  // 先删消息，再删会话
  await db.delete(
    'messages',
    where: 'session_id IN ($placeholders)',
    whereArgs: ids,
  );
  final count = await db.delete(
    'sessions',
    where: 'id IN ($placeholders)',
    whereArgs: ids,
  );
  return count;
}

/// 查询所有已逻辑删除的会话（回收站列表）
Future<List<ChatSessionModel>> loadDeletedSessions() async {
  final db = await database;
  final rows = await db.query(
    'sessions',
    where: 'deleted_at IS NOT NULL',
    orderBy: 'deleted_at DESC',
  );
  // 解析逻辑同 loadSessions，此处省略
  return _parseSessionRows(rows);
}
```

Claude 实例表同理：

```dart
/// 逻辑删除 Claude 实例记录
Future<void> softDeleteInstance(String instanceId) async {
  final db = await database;
  await db.update(
    'claude_instances',
    {'deleted_at': DateTime.now().millisecondsSinceEpoch},
    where: 'id = ?',
    whereArgs: [instanceId],
  );
}

/// 物理删除超过 7 天的 Claude 实例记录
Future<int> purgeExpiredInstances() async {
  final db = await database;
  final cutoff = DateTime.now()
      .subtract(const Duration(days: 7))
      .millisecondsSinceEpoch;
  return await db.delete(
    'claude_instances',
    where: 'deleted_at IS NOT NULL AND deleted_at < ?',
    whereArgs: [cutoff],
  );
}
```

### 4.4 查询过滤

所有正常列表查询追加过滤条件，只返回未删除的记录：

```dart
/// 获取所有未删除的会话
Future<List<ChatSessionModel>> loadSessions() async {
  final db = await database;
  final rows = await db.query(
    'sessions',
    where: 'deleted_at IS NULL',   // 过滤已删除
    orderBy: 'updated_at DESC',
  );
  // ...
}
```

### 4.5 定时清理任务

在 `AppStateProvider.initialize()` 中注册自动清理 Cron：

```dart
/// 注册每日凌晨 3 点执行的过期数据清理任务
void _registerPurgeSchedule() {
  _cronService.registerSystemTask(
    id: 'sys_purge_deleted',
    schedule: '0 3 * * *',
    onExecute: () async {
      final sessionCount = await _dbService.purgeExpiredSessions();
      final instanceCount = await _dbService.purgeExpiredInstances();
      if (sessionCount > 0 || instanceCount > 0) {
        await _dbService.insertTaskLog(TaskLogModel(
          id: 'log_purge_${DateTime.now().millisecondsSinceEpoch}',
          taskId: 'sys_purge_deleted',
          taskName: '过期数据清理',
          executedAt: DateTime.now(),
          durationMs: 0,
          isSuccess: true,
          output: '清理会话 $sessionCount 条，实例 $instanceCount 条',
        ));
      }
    },
  );
}
```

### 4.6 UI 交互

| 操作 | 行为 |
|------|------|
| 删除会话 | 调用 `softDeleteSession`，列表立即隐藏，底部弹出 Snackbar 提示"已删除，可在回收站恢复" |
| 回收站入口 | 侧边栏会话列表底部增加"回收站"入口，展示 `loadDeletedSessions` 列表 |
| 恢复操作 | 回收站中每条记录提供"恢复"按钮，调用 `restoreSession` |
| 彻底删除 | 回收站中提供"彻底删除"按钮，直接物理删除 |
| 自动清理 | 每日凌晨 3 点自动清理超过 7 天的记录 |

---

## 五、数据库升级方案

在现有 `DatabaseService._initDatabase()` 中追加迁移版本：

```dart
// version 1 -> 2 迁移
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 2) {
    // 现有 sessions 表追加软删除字段
    await db.execute('ALTER TABLE sessions ADD COLUMN deleted_at INTEGER');

    // Profile 表
    await db.execute('''
      CREATE TABLE claude_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        auth_type TEXT NOT NULL DEFAULT 'oauth',
        api_key_ref TEXT,
        config_dir TEXT NOT NULL,
        model TEXT,
        permission_mode TEXT,
        env_overrides TEXT,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER NOT NULL
      )
    ''');

    // 进程实例记录表
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
  }
},
```

数据库版本号从 `1` 升至 `2`。

---

## 五、新增依赖

在 `pubspec.yaml` 中新增：

```yaml
dependencies:
  flutter_secure_storage: ^11.0.0   # 系统安全凭证存储
  xterm: ^4.0.0                      # 终端输出渲染组件
  file_picker: ^8.0.0               # 系统文件选择器
  desktop_drop: ^0.5.0              # 桌面拖放支持
  pasteboard: ^0.3.0                # 剪贴板图片读取
```

---

## 六、UI 页面规划

### 6.1 新增侧边栏入口

在 `HomeView` 侧边栏增加两个导航项：

| 位置 | 图标 | 名称 | 对应页面 |
|------|------|------|----------|
| 定时任务上方 | `Icons.terminal_outlined` | Claude | `ClaudeManagerView` |

### 6.2 ClaudeManagerView 页面结构

页面采用上下分栏布局：

```
┌─────────────────────────────────────────┐
│ 顶部：环境状态栏                         │
│ [已安装 v1.0.33] [/usr/local/bin/claude] │
│ [未安装 → 点击安装引导]                   │
├─────────────────────────────────────────┤
│ 左侧 Profile 列表  │  右侧工作区         │
│                    │                     │
│ ┌───────────────┐  │  Tab 1: Profile 详情│
│ │ 工作账号      │  │  Tab 2: 活跃实例    │
│ │ 个人账号      │  │  Tab 3: 任务历史    │
│ │ + 新建        │  │                     │
│ └───────────────┘  │                     │
│                    │  ┌───────────────┐  │
│                    │  │ 实例 1 输出流  │  │
│                    │  │ 实例 2 输出流  │  │
│                    │  │ + 新建实例     │  │
│                    │  └───────────────┘  │
└─────────────────────────────────────────┘
```

### 6.3 多任务工作台面板

每个运行中的实例显示为一个独立卡片：

```
┌─────────────────────────────────┐
│ 实例 #1  [工作账号]  [运行中]    │
│ 工作目录: /Users/xxx/project-a  │
│ 会话: auth-refactor             │
│ 耗时: 2m 34s  费用: $0.12       │
├─────────────────────────────────┤
│ > 正在分析 src/auth/login.dart  │
│ > 修改了 3 个文件               │
│ > 运行测试...通过               │
├─────────────────────────────────┤
│ [中止]  [查看详情]  [发送指令]   │
└─────────────────────────────────┘
```

---

## 七、文件与图片附件支持

### 7.1 实现原理

Claude Code CLI 在 prompt 中引用文件绝对路径时，会自动识别并读取文件内容：

- **图片文件** - Claude Code 通过视觉能力分析图片
- **文本文件** - Claude Code 通过 Read 工具读取文件内容

两类文件处理链路统一：用户添加附件 -> 复制到实例工作目录 -> prompt 中拼接路径引用 -> 发送给 Claude Code 进程。

### 7.2 附件分类

| 类别 | 扩展名 | prompt 引用方式 | 预览方式 |
|------|--------|----------------|----------|
| 图片 | png/jpg/jpeg/gif/webp | 路径引用，Claude 视觉分析 | 缩略图 |
| 文档 | txt/md/json/yaml/xml/csv/log | 路径引用，Claude 读取内容 | 文件名 + 大小 |
| 代码 | dart/js/ts/py/go/java/rs/c/cpp/h/swift/kt | 路径引用，Claude 读取内容 | 文件名 + 语言标签 |

### 7.3 附件数据模型

```dart
/// 附件类型
enum AttachmentType {
  image,    // 图片
  document, // 文档
  code,     // 代码文件
}

/// 单个附件
class Attachment {
  final String id;
  final String originalPath;  // 用户选择的原始路径
  final String stagedPath;    // 暂存到工作目录后的路径
  final String fileName;
  final int fileSize;         // 字节数
  final AttachmentType type;

  const Attachment({
    required this.id,
    required this.originalPath,
    required this.stagedPath,
    required this.fileName,
    required this.fileSize,
    required this.type,
  });
}
```

### 7.4 附件管理服务 (`attachment_service.dart`)

```dart
/// 文件附件管理服务
class AttachmentService {
  /// 图片扩展名集合
  static const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp'};

  /// 代码扩展名集合
  static const _codeExts = {
    'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'go', 'java',
    'rs', 'c', 'cpp', 'h', 'swift', 'kt', 'rb', 'php',
    'sh', 'sql', 'html', 'css', 'scss', 'vue',
  };

  /// 判断附件类型
  AttachmentType resolveType(String filePath) {
    final ext = path.extension(filePath).replaceFirst('.', '').toLowerCase();
    if (_imageExts.contains(ext)) return AttachmentType.image;
    if (_codeExts.contains(ext)) return AttachmentType.code;
    return AttachmentType.document;
  }

  /// 将文件暂存到实例工作目录，返回 Attachment 对象
  Future<Attachment> stageFile({
    required String sourcePath,
    required String instanceWorkDir,
  }) async {
    final assetsDir = Directory('$instanceWorkDir/.agenthub_assets');
    if (!assetsDir.existsSync()) {
      assetsDir.createSync(recursive: true);
    }

    final sourceFile = File(sourcePath);
    final fileName = path.basename(sourcePath);
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final destPath = '${assetsDir.path}/$uniqueName';
    await sourceFile.copy(destPath);

    return Attachment(
      id: uniqueName,
      originalPath: sourcePath,
      stagedPath: destPath,
      fileName: fileName,
      fileSize: await sourceFile.length(),
      type: resolveType(sourcePath),
    );
  }

  /// 将附件列表拼接到用户文本中，生成最终 prompt
  String buildPromptWithAttachments({
    required String userText,
    required List<Attachment> attachments,
  }) {
    if (attachments.isEmpty) return userText;

    final buffer = StringBuffer(userText);
    buffer.writeln();

    // 按类型分组引用
    final images = attachments.where((a) => a.type == AttachmentType.image).toList();
    final files = attachments.where((a) => a.type != AttachmentType.image).toList();

    if (images.isNotEmpty) {
      for (int i = 0; i < images.length; i++) {
        buffer.writeln('图片${i + 1}: ${images[i].stagedPath}');
      }
    }
    if (files.isNotEmpty) {
      for (int i = 0; i < files.length; i++) {
        buffer.writeln('附件${i + 1}: ${files[i].stagedPath}');
      }
    }

    return buffer.toString();
  }

  /// 清理指定实例的暂存附件
  Future<void> cleanAssets(String instanceWorkDir) async {
    final assetsDir = Directory('$instanceWorkDir/.agenthub_assets');
    if (assetsDir.existsSync()) {
      await assetsDir.delete(recursive: true);
    }
  }
}
```

### 7.5 UI 交互

输入栏增加附件按钮，图片和文件统一管理：

```
┌──────────────────────────────────────────────────────┐
│  [附件预览区]                                         │
│  ┌──────┐ ┌────────────────┐ ┌────────────────┐      │
│  │ x    │ │ x              │ │ x              │      │
│  │ img1 │ │ readme.md 2KB  │ │ main.dart 8KB  │      │
│  │[缩略]│ │ [文档]         │ │ [dart]         │      │
│  └──────┘ └────────────────┘ └────────────────┘      │
├──────────────────────────────────────────────────────┤
│ [附件] 请根据文档和设计稿实现这个功能          [发送]  │
└──────────────────────────────────────────────────────┘
```

**支持的输入方式：**

| 方式 | 实现 | 说明 |
|------|------|------|
| 点击按钮选择 | `file_picker` | 支持多选，不限文件类型 |
| 拖拽到输入区 | `desktop_drop` | 支持同时拖入多个文件 |
| 粘贴剪贴板 | `pasteboard` | 仅图片，截图后直接粘贴 |

### 7.6 进程管理器扩展

`ClaudeProcessManager.executeStreaming` 方法使用通用附件参数：

```dart
/// 以流式模式执行任务（支持文件和图片附件）
Stream<ClaudeStreamEvent> executeStreaming({
  required String instanceId,
  required String prompt,
  List<String>? attachmentPaths,  // 文件路径列表（图片+文档+代码）
}) async* {
  final instance = _instances[instanceId];
  if (instance == null) return;

  // 暂存附件并拼接 prompt
  String finalPrompt = prompt;
  if (attachmentPaths != null && attachmentPaths.isNotEmpty) {
    final attachments = <Attachment>[];
    for (final src in attachmentPaths) {
      final att = await _attachmentService.stageFile(
        sourcePath: src,
        instanceWorkDir: instance.workDir,
      );
      attachments.add(att);
    }
    finalPrompt = _attachmentService.buildPromptWithAttachments(
      userText: prompt,
      attachments: attachments,
    );
  }

  final execPath = await _envService.getExecutablePath();
  final args = ['-p', '--output-format', 'stream-json', finalPrompt];
  // ... 启动进程、解析流
}
```

### 7.7 新增依赖

```yaml
dependencies:
  file_picker: ^8.0.0      # 系统文件选择器
  desktop_drop: ^0.5.0      # 桌面拖放支持
  pasteboard: ^0.3.0        # 剪贴板图片读取
```

---

## 八、文件结构规划

```
lib/
├── models/
│   ├── claude_env_info.dart          # 环境信息模型
│   ├── claude_profile.dart           # Profile 模型
│   ├── claude_process_instance.dart   # 进程实例模型
│   ├── claude_stream_event.dart       # 流式事件模型
│   └── attachment.dart               # 附件模型（图片/文档/代码）
├── services/
│   ├── claude_env_service.dart        # 环境检测服务
│   ├── claude_profile_service.dart    # Profile 管理服务
│   ├── claude_process_manager.dart    # 进程管理器
│   ├── credential_service.dart        # 安全凭证服务（Keychain）
│   └── attachment_service.dart        # 通用附件管理服务
├── widgets/
│   └── attachment_input.dart          # 附件选择与输入组件
└── views/
    ├── claude_manager_view.dart        # Claude 管理主页面
    └── trash_view.dart                 # 会话回收站页面
```

---

## 九、新增依赖汇总

在 `pubspec.yaml` 中新增：

```yaml
dependencies:
  flutter_secure_storage: ^11.0.0   # 系统安全凭证存储 (macOS Keychain / Windows Credential)
  xterm: ^4.0.0                      # 终端控制台流式渲染组件
  file_picker: ^8.0.0               # 系统文件选择器 (图片、文本、代码多选)
  desktop_drop: ^0.5.0              # 桌面文件拖放监听
  pasteboard: ^0.3.0                # 剪贴板图片读取与粘贴
```

---

## 十、关键技术点

### 10.1 多实例隔离机制

每个 Claude Code 实例通过以下方式实现完全隔离：

1. **配置目录隔离**：每个 Profile 分配专用目录，通过 `CLAUDE_CONFIG_DIR` 环境变量传入，OAuth 凭据与内部配置彻底物理分开。
2. **工作目录隔离**：每个实例创建时指定对应项目的 `workingDirectory`。
3. **进程独立**：每个实例为独立的 OS 子进程，标准输出输出流单独管理，崩溃或终止互不影响。
4. **安全凭据隔离**：API Key 通过系统 Keychain 按 Profile ID 键名隔离存取。
5. **会话隔离**：通过 `--resume <session_id>` 独立恢复对应实例的上下文。

### 10.2 Claude Code CLI 关键参数

| 参数 | 用途 |
|------|------|
| `-p` / `--print` | 非交互模式，执行任务并输出结果 |
| `--output-format stream-json` | NDJSON 流式输出，实时捕获事件与进度 |
| `--output-format json` | 单次完整 JSON 输出，包含结果、费用与耗时 |
| `--resume <session-id>` | 恢复指定会话上下文 |
| `--model <model>` | 指定执行模型 |
| `--allowedTools` | 工具白名单限制 |
| `--permission-mode` | 权限执行策略 |
| `--bare` | 跳过环境与配置文件自检 |

### 10.3 环境变量注入

| 变量名 | 用途 |
|--------|------|
| `CLAUDE_CONFIG_DIR` | 指定当前 Profile 独立配置目录 |
| `ANTHROPIC_API_KEY` | API Key 授权凭据 |
| `ANTHROPIC_MODEL` | 模型名称 |

---

## 十一、实施阶段规划

### 阶段一：底层存储与安全基础设施
1. 添加 `flutter_secure_storage`，配置 macOS entitlements 权限。
2. 实现 `CredentialService`，封装安全存取。
3. 数据库升级至 Version 2：
   - 现有 `sessions` 表增加 `deleted_at` 字段支持软删除。
   - 新建 `claude_profiles` 表与 `claude_instances` 表。
4. 实现 `DatabaseService` 中的软删除、回收站查询与 7 天过期物理清理逻辑。

### 阶段二：环境检测与 Profile 账号管理
1. 实现 `ClaudeEnvService`：
   - `which claude` 路径获取与安装状态检测。
   - `claude --version` 解析。
   - 未安装时的引导及检测 Node.js 环境。
2. 实现 `ClaudeProfileService`：
   - Profile 增删改查。
   - 独立配置目录 `~/.agenthub/claude_profiles/<id>/` 初始化。
   - 凭证与环境变量合成。
3. UI 页面接入：Profile 列表、创建/编辑抽屉、状态切换。

### 阶段三：附件系统与进程调度
1. 实现 `AttachmentService`：
   - 支持图片、txt、md、代码文件的类型识别与工作区暂存。
   - prompt 引用文本自动注入。
2. 实现输入组件 `AttachmentInput`：
   - 文件选择器 `file_picker` 多选。
   - 桌面拖放 `desktop_drop`。
   - 剪贴板图片 `pasteboard` 快捷粘贴。
   - 附件缩略标签与一键移除。
3. 实现 `ClaudeProcessManager`：
   - 子进程启动与环境变量隔离。
   - stream-json 流式事件解析与分发。
   - 进程中止与状态流转。

### 阶段四：多任务 AI 编程工作台与回收站
1. 多任务实例面板开发：
   - 多卡片并行查看任务状态（运行中、空闲、异常）。
   - 单实例终端流式日志输出组件集成。
   - 任务发起、停止、追问与会话恢复。
2. 会话软删除与回收站完整联动：
   - 列表右键/操作列点击软删除。
   - 侧边栏底部回收站入口。
   - 回收站列表恢复与彻底删除。
   - 系统 Cron 每日凌晨 3 点执行 7 天过期自动清理。

---

## 十二、风险与注意事项

1. **OAuth 授权多目录兼容**：使用 `CLAUDE_CONFIG_DIR` 时，首次切换新 Profile 需在此配置目录下完成一次认证。
2. **多进程并发资源保护**：桌面端建议设定最大并行活跃进程数（如 4-6 个），防止大量并发导致内存或 CPU 过载。
3. **macOS 签名限制**：开发与调试时确保 entitlements 中配置了 keychain-access-groups，防止安全存储报权限错误。
4. **大文件附件截断处理**：用户传入极大的 txt 或日志文件时，应在前端或服务层设置体积提示，避免触发上下文超限。

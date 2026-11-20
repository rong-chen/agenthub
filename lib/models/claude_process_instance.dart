import 'dart:async';
import 'dart:io';

/// 实例状态枚举
enum ClaudeProcessStatus {
  idle,       // 空闲就绪
  running,    // 正在运行
  streaming,  // 流式输出中
  error,      // 执行出错
  terminated, // 已终止
}

/// Claude Code 进程实例模型
class ClaudeProcessInstance {
  final String id;
  String profileId;
  String workDir;
  String? sessionId;
  String? claudeResumeUuid;
  ClaudeProcessStatus status;
  String? currentTask;
  DateTime startedAt;
  String? lastOutput;
  DateTime? deletedAt;

  Process? process;
  final StreamController<String> outputController = StreamController<String>.broadcast();
  final List<String> logs = [];

  ClaudeProcessInstance({
    required this.id,
    required this.profileId,
    required this.workDir,
    this.sessionId,
    this.status = ClaudeProcessStatus.idle,
    this.currentTask,
    required this.startedAt,
    this.lastOutput,
    this.deletedAt,
  });

  /// 添加输出日志
  void appendLog(String log) {
    logs.add(log);
    lastOutput = log;
    outputController.add(log);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_id': profileId,
      'work_dir': workDir,
      'session_id': sessionId,
      'status': status.name,
      'current_task': currentTask,
      'started_at': startedAt.millisecondsSinceEpoch,
      'last_output': lastOutput,
      'deleted_at': deletedAt?.millisecondsSinceEpoch,
    };
  }

  factory ClaudeProcessInstance.fromMap(Map<String, dynamic> map) {
    return ClaudeProcessInstance(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      workDir: map['work_dir'] as String,
      sessionId: map['session_id'] as String?,
      status: ClaudeProcessStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => ClaudeProcessStatus.idle,
      ),
      currentTask: map['current_task'] as String?,
      startedAt: DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
      lastOutput: map['last_output'] as String?,
      deletedAt: map['deleted_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int)
          : null,
    );
  }

  void dispose() {
    outputController.close();
  }
}

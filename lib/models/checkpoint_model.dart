import 'dart:convert';

/// 工作区文件变更快照与检查点模型
class CheckpointModel {
  final String id;
  final String sessionId;
  final String messageId;
  final String workDir;
  final List<String> changedFiles;
  final String diffSummary;
  final String? diffContent;
  final String backupDir;
  final DateTime createdAt;
  bool isRolledBack;

  CheckpointModel({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.workDir,
    required this.changedFiles,
    required this.diffSummary,
    this.diffContent,
    required this.backupDir,
    required this.createdAt,
    this.isRolledBack = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'message_id': messageId,
      'work_dir': workDir,
      'changed_files': jsonEncode(changedFiles),
      'diff_summary': diffSummary,
      'diff_content': diffContent,
      'backup_dir': backupDir,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_rolled_back': isRolledBack ? 1 : 0,
    };
  }

  factory CheckpointModel.fromMap(Map<String, dynamic> map) {
    List<String> files = [];
    final rawFiles = map['changed_files'];
    if (rawFiles is String && rawFiles.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFiles);
        if (decoded is List) {
          files = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return CheckpointModel(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      messageId: map['message_id'] as String,
      workDir: map['work_dir'] as String,
      changedFiles: files,
      diffSummary: map['diff_summary'] as String? ?? '',
      diffContent: map['diff_content'] as String?,
      backupDir: map['backup_dir'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isRolledBack: (map['is_rolled_back'] as int? ?? 0) == 1,
    );
  }
}

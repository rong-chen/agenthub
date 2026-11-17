/// 定时计划任务真实运行日志模型
class TaskLogModel {
  final String id;
  final String taskId;
  final String taskName;
  final DateTime executedAt;
  final int durationMs;
  final bool isSuccess;
  final String output;

  TaskLogModel({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.executedAt,
    required this.durationMs,
    required this.isSuccess,
    required this.output,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'taskName': taskName,
        'executedAt': executedAt.toIso8601String(),
        'durationMs': durationMs,
        'isSuccess': isSuccess,
        'output': output,
      };

  factory TaskLogModel.fromJson(Map<String, dynamic> json) {
    return TaskLogModel(
      id: json['id']?.toString() ?? '',
      taskId: json['taskId']?.toString() ?? '',
      taskName: json['taskName']?.toString() ?? '',
      executedAt: json['executedAt'] != null
          ? DateTime.tryParse(json['executedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      isSuccess: json['isSuccess'] as bool? ?? false,
      output: json['output']?.toString() ?? '',
    );
  }
}

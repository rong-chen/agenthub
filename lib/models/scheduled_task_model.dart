/// 定时计划任务数据模型
class ScheduledTaskModel {
  final String id;
  String name;
  String schedule; // Cron 表达式 (如: */30 * * * *, 0 3 * * *) 或标准描述
  String? tag;
  DateTime? nextRun;
  DateTime? lastRun;
  bool isEnabled;
  String actionType; // gateway_check, skills_reload, shell_cmd
  String command; // 动作对应指令或脚本
  String? lastStatus;

  ScheduledTaskModel({
    required this.id,
    required this.name,
    required this.schedule,
    this.tag,
    this.nextRun,
    this.lastRun,
    this.isEnabled = true,
    this.actionType = 'gateway_check',
    this.command = '',
    this.lastStatus,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'schedule': schedule,
        'tag': tag,
        'nextRun': nextRun?.toIso8601String(),
        'lastRun': lastRun?.toIso8601String(),
        'isEnabled': isEnabled,
        'actionType': actionType,
        'command': command,
        'lastStatus': lastStatus,
      };

  factory ScheduledTaskModel.fromJson(Map<String, dynamic> json) {
    return ScheduledTaskModel(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name']?.toString() ?? '',
      schedule: json['schedule']?.toString() ?? '*/30 * * * *',
      tag: json['tag']?.toString(),
      nextRun: json['nextRun'] != null ? DateTime.tryParse(json['nextRun'].toString()) : null,
      lastRun: json['lastRun'] != null ? DateTime.tryParse(json['lastRun'].toString()) : null,
      isEnabled: json['isEnabled'] as bool? ?? true,
      actionType: json['actionType']?.toString() ?? 'gateway_check',
      command: json['command']?.toString() ?? '',
      lastStatus: json['lastStatus']?.toString(),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import '../models/scheduled_task_model.dart';
import '../utils/path_utils.dart';

/// 定时计划任务存储与调度管理服务
class TaskService {
  /// 获取定时任务配置文件路径
  Future<File> get _tasksFile async {
    final rootPath = PathUtils.agentHubRootDir;
    return File('$rootPath/tasks.json');
  }

  /// 加载所有定时计划任务
  Future<List<ScheduledTaskModel>> loadTasks() async {
    try {
      final file = await _tasksFile;
      if (!await file.exists()) {
        final initialTasks = _createDefaultTasks();
        await saveTasks(initialTasks);
        return initialTasks;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded
            .map((item) => ScheduledTaskModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (_) {
      // 容错读取失败情况
    }
    return [];
  }

  /// 保存任务列表至本地磁盘
  Future<void> saveTasks(List<ScheduledTaskModel> tasks) async {
    try {
      final file = await _tasksFile;
      final jsonList = tasks.map((t) => t.toJson()).toList();
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonList));
    } catch (_) {
      // 容错持久化异常
    }
  }

  /// 执行一次指定任务并更新其运行时间
  Future<void> triggerTask(ScheduledTaskModel task) async {
    task.lastRun = DateTime.now();
    task.nextRun = _calculateNextRun(task.schedule);
  }

  /// 计算下一次运行时间估算
  DateTime _calculateNextRun(String schedule) {
    final now = DateTime.now();
    final lower = schedule.toLowerCase();
    if (lower.contains('30分钟') || lower.contains('30m')) {
      return now.add(const Duration(minutes: 30));
    }
    if (lower.contains('7天') || lower.contains('7d')) {
      return now.add(const Duration(days: 7));
    }
    if (lower.contains('cron') || lower.contains('小时')) {
      return now.add(const Duration(hours: 9));
    }
    return now.add(const Duration(hours: 1));
  }

  /// 预设 OpenClaw 标准后台定时任务
  List<ScheduledTaskModel> _createDefaultTasks() {
    final now = DateTime.now();
    return [
      ScheduledTaskModel(
        id: 'task_heartbeat',
        name: 'heartbeat-main',
        schedule: 'Every 30分钟',
        lastRun: now.subtract(const Duration(minutes: 26)),
        nextRun: now.add(const Duration(minutes: 4)),
        isEnabled: true,
        command: 'ping_gateway',
      ),
      ScheduledTaskModel(
        id: 'task_memory',
        name: 'Memory Dreaming Promotion',
        schedule: 'Cron 0 3 * * *',
        tag: 'managed-by=memory-core.short-term-pr...',
        lastRun: null,
        nextRun: now.add(const Duration(hours: 9)),
        isEnabled: true,
        command: 'promote_memory',
      ),
      ScheduledTaskModel(
        id: 'task_skill_review',
        name: 'skill-collection-review-main',
        schedule: 'Every 7天',
        lastRun: null,
        nextRun: now.add(const Duration(days: 6)),
        isEnabled: true,
        command: 'review_skills',
      ),
    ];
  }
}

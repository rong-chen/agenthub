import 'dart:async';
import 'dart:io';
import 'package:cron/cron.dart';
import 'package:http/http.dart' as http;
import '../models/scheduled_task_model.dart';
import '../models/task_log_model.dart';
import 'database_service.dart';

/// 真实的 Cron 定时任务调度与执行引擎
class CronSchedulerService {
  static final CronSchedulerService instance = CronSchedulerService._internal();
  CronSchedulerService._internal();

  final Cron _cron = Cron();
  final Map<String, ScheduledTask> _scheduledTasks = {};

  /// 解析定时表达式为 Cron Schedule 对象
  Schedule? _parseSchedule(String expression) {
    final trimmed = expression.trim();
    try {
      // 兼容标准 5 段式 Cron 表达式
      if (trimmed.split(RegExp(r'\s+')).length == 5) {
        return Schedule.parse(trimmed);
      }
      // 周期表述转换为标准 Cron
      if (trimmed.contains('1分钟') || trimmed.contains('1m')) {
        return Schedule.parse('*/1 * * * *');
      }
      if (trimmed.contains('5分钟') || trimmed.contains('5m')) {
        return Schedule.parse('*/5 * * * *');
      }
      if (trimmed.contains('10分钟') || trimmed.contains('10m')) {
        return Schedule.parse('*/10 * * * *');
      }
      if (trimmed.contains('30分钟') || trimmed.contains('30m')) {
        return Schedule.parse('*/30 * * * *');
      }
      if (trimmed.contains('1小时') || trimmed.contains('1h')) {
        return Schedule.parse('0 * * * *');
      }
      if (trimmed.contains('每天') || trimmed.contains('1天')) {
        return Schedule.parse('0 0 * * *');
      }
    } catch (_) {
      // 格式异常保护
    }
    return null;
  }

  /// 计算下一次预计执行时间
  DateTime calculateNextRun(String scheduleStr, [DateTime? from]) {
    final base = from ?? DateTime.now();
    final trimmed = scheduleStr.trim();
    if (trimmed.contains('1m') || trimmed.contains('1分钟') || trimmed == '* * * * *' || trimmed == '*/1 * * * *') {
      return base.add(const Duration(minutes: 1));
    }
    if (trimmed.contains('5m') || trimmed.contains('5分钟') || trimmed == '*/5 * * * *') {
      return base.add(const Duration(minutes: 5));
    }
    if (trimmed.contains('10m') || trimmed.contains('10分钟') || trimmed == '*/10 * * * *') {
      return base.add(const Duration(minutes: 10));
    }
    if (trimmed.contains('30m') || trimmed.contains('30分钟') || trimmed == '*/30 * * * *') {
      return base.add(const Duration(minutes: 30));
    }
    if (trimmed.contains('1h') || trimmed.contains('1小时') || trimmed == '0 * * * *') {
      return base.add(const Duration(hours: 1));
    }
    if (trimmed.contains('1d') || trimmed.contains('每天') || trimmed == '0 0 * * *') {
      return DateTime(base.year, base.month, base.day + 1, 0, 0);
    }
    final match = RegExp(r'\*/(\d+)\s+\*\s+\*\s+\*\s+\*').firstMatch(trimmed);
    if (match != null) {
      final mins = int.tryParse(match.group(1) ?? '30') ?? 30;
      return base.add(Duration(minutes: mins));
    }
    return base.add(const Duration(minutes: 30));
  }

  /// 同步并更新全部激活的任务调度器
  void syncTasks(
    List<ScheduledTaskModel> tasks, {
    required int gatewayPort,
    required Future<void> Function() onSkillsReload,
    required void Function() onTaskExecuted,
  }) {
    // 先取消当前已注册的调度任务
    for (final task in _scheduledTasks.values) {
      task.cancel();
    }
    _scheduledTasks.clear();

    // 重新注册所有激活状态的任务
    for (final task in tasks) {
      if (!task.isEnabled) {
        continue;
      }

      final schedule = _parseSchedule(task.schedule);
      if (schedule == null) {
        continue;
      }

      try {
        final scheduled = _cron.schedule(schedule, () async {
          await executeTask(
            task,
            gatewayPort: gatewayPort,
            onSkillsReload: onSkillsReload,
          );
          onTaskExecuted();
        });
        _scheduledTasks[task.id] = scheduled;
      } catch (_) {
        // 调度注册异常保护
      }
    }
  }

  /// 真实执行一次任务并记录持久化日志到 SQLite
  Future<TaskLogModel> executeTask(
    ScheduledTaskModel task, {
    required int gatewayPort,
    required Future<void> Function() onSkillsReload,
  }) async {
    final startTime = DateTime.now();
    bool isSuccess = false;
    String output = '';

    try {
      if (task.actionType == 'gateway_check') {
        // 检测网关连通状态
        final url = Uri.parse('http://127.0.0.1:$gatewayPort/health');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        isSuccess = res.statusCode == 200;
        output = isSuccess ? '服务正常' : '未响应';
      } else if (task.actionType == 'skills_reload') {
        // 重新扫描并更新插件
        await onSkillsReload();
        isSuccess = true;
        output = '插件已更新';
      } else if (task.actionType == 'shell_cmd') {
        // 执行系统命令
        final cmd = task.command.trim();
        if (cmd.isNotEmpty) {
          final ProcessResult result;
          if (Platform.isWindows) {
            result = await Process.run(
              'cmd.exe',
              ['/c', cmd],
              runInShell: true,
            ).timeout(const Duration(seconds: 15));
          } else {
            result = await Process.run(
              'sh',
              ['-c', cmd],
              runInShell: true,
            ).timeout(const Duration(seconds: 15));
          }
          isSuccess = result.exitCode == 0;
          final outText = result.stdout.toString().trim();
          final errText = result.stderr.toString().trim();
          output = isSuccess
              ? (outText.isNotEmpty ? outText : '执行完成')
              : (errText.isNotEmpty ? errText : '执行未完成');
        } else {
          isSuccess = false;
          output = '未设置执行内容';
        }
      } else {
        isSuccess = true;
        output = '执行完成';
      }
    } catch (_) {
      isSuccess = false;
      output = '执行未完成';
    }

    final durationMs = DateTime.now().difference(startTime).inMilliseconds;
    final log = TaskLogModel(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      taskId: task.id,
      taskName: task.name,
      executedAt: startTime,
      durationMs: durationMs,
      isSuccess: isSuccess,
      output: output,
    );

    // 更新任务运行时间与预计下次执行时间
    task.lastRun = startTime;
    task.nextRun = calculateNextRun(task.schedule, startTime);
    task.lastStatus = isSuccess ? 'success' : 'error';
    await DatabaseService.instance.saveTask(task);
    await DatabaseService.instance.insertTaskLog(log);

    return log;
  }

  /// 停止调度引擎
  void dispose() {
    for (final task in _scheduledTasks.values) {
      task.cancel();
    }
    _scheduledTasks.clear();
    _cron.close();
  }
}

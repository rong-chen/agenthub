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
      // 常见中文/周期表述转换为标准 Cron
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
      // 表达式不合法时返回 null
    }
    return null;
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
        // 真实网关健康心跳检测
        final url = Uri.parse('http://127.0.0.1:$gatewayPort/health');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        isSuccess = res.statusCode == 200;
        output = '网关 HTTP 响应状态: ${res.statusCode}, 内容: ${res.body}';
      } else if (task.actionType == 'skills_reload') {
        // 真实重新扫描并加载技能
        await onSkillsReload();
        isSuccess = true;
        output = '本地技能目录已重新扫描并更新完毕';
      } else if (task.actionType == 'shell_cmd') {
        // 真实执行本地命令
        final cmd = task.command.trim();
        if (cmd.isNotEmpty) {
          final result = await Process.run(
            'bash',
            ['-c', cmd],
            runInShell: true,
          ).timeout(const Duration(seconds: 15));
          isSuccess = result.exitCode == 0;
          output = isSuccess
              ? result.stdout.toString().trim()
              : '执行报错: ${result.stderr.toString().trim()}';
        } else {
          isSuccess = true;
          output = '未指定具体 shell 指令';
        }
      } else {
        isSuccess = true;
        output = '默认周期性巡检完成';
      }
    } catch (e) {
      isSuccess = false;
      output = '执行发生异常: $e';
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

    // 更新任务最近运行状态并持久化至 SQLite
    task.lastRun = startTime;
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

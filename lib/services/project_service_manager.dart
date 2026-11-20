import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 服务运行状态枚举
enum ServiceStatus {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// 服务控制台单条日志数据结构
class ServiceLogLine {
  final DateTime timestamp;
  final String text;
  final bool isError;

  ServiceLogLine({
    required this.timestamp,
    required this.text,
    this.isError = false,
  });
}

/// 单个会话或项目对应的服务运行实例
class ProjectServiceInstance {
  final String sessionId;
  final String workDir;
  String command;
  ServiceStatus status = ServiceStatus.stopped;
  Process? process;
  int? pid;
  DateTime? startedAt;
  final List<ServiceLogLine> logs = [];
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  ProjectServiceInstance({
    required this.sessionId,
    required this.workDir,
    this.command = '',
  });

  /// 添加单条日志并控制最大缓存行数
  void appendLog(String line, {bool isError = false}) {
    final now = DateTime.now();
    logs.add(ServiceLogLine(
      timestamp: now,
      text: line,
      isError: isError,
    ));
    // 限制单服务最大日志量为 5000 行
    if (logs.length > 5000) {
      logs.removeRange(0, logs.length - 5000);
    }
  }

  /// 清空日志
  void clearLogs() {
    logs.clear();
  }

  /// 释放进程流资源
  void disposeSubscriptions() {
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
  }
}

/// 项目服务管理调度服务（负责本地 Web/后端服务的拉起、停止、重启与日志流捕获）
class ProjectServiceManager extends ChangeNotifier {
  static final ProjectServiceManager instance = ProjectServiceManager._internal();
  ProjectServiceManager._internal();

  final Map<String, ProjectServiceInstance> _services = {};

  /// 获取指定会话的服务实例
  ProjectServiceInstance getOrCreateInstance(String sessionId, String workDir) {
    if (!_services.containsKey(sessionId)) {
      final defaultCmd = detectDefaultCommand(workDir);
      _services[sessionId] = ProjectServiceInstance(
        sessionId: sessionId,
        workDir: workDir,
        command: defaultCmd,
      );
    }
    return _services[sessionId]!;
  }

  /// 查询指定会话的服务实例
  ProjectServiceInstance? getInstance(String sessionId) {
    return _services[sessionId];
  }

  /// 智能探测工作目录下的建议启动命令
  String detectDefaultCommand(String workDir) {
    if (workDir.isEmpty || !Directory(workDir).existsSync()) {
      return '';
    }

    try {
      // 1. Node.js 项目探测
      final pkgFile = File(p.join(workDir, 'package.json'));
      if (pkgFile.existsSync()) {
        try {
          final content = pkgFile.readAsStringSync();
          final json = jsonDecode(content);
          if (json is Map && json['scripts'] is Map) {
            final scripts = json['scripts'] as Map;
            if (scripts.containsKey('dev')) return 'npm run dev';
            if (scripts.containsKey('start')) return 'npm start';
            if (scripts.containsKey('serve')) return 'npm run serve';
          }
        } catch (_) {}
        return 'npm start';
      }

      // 2. Flutter / Dart 项目探测
      final pubspecFile = File(p.join(workDir, 'pubspec.yaml'));
      if (pubspecFile.existsSync()) {
        return 'flutter run';
      }

      // 3. Python 项目探测
      if (File(p.join(workDir, 'main.py')).existsSync()) {
        return 'python3 main.py';
      }
      if (File(p.join(workDir, 'app.py')).existsSync()) {
        return 'python3 app.py';
      }
      if (File(p.join(workDir, 'manage.py')).existsSync()) {
        return 'python3 manage.py runserver';
      }

      // 4. Go 项目探测
      if (File(p.join(workDir, 'go.mod')).existsSync()) {
        return 'go run .';
      }

      // 5. Rust 项目探测
      if (File(p.join(workDir, 'Cargo.toml')).existsSync()) {
        return 'cargo run';
      }
    } catch (_) {}

    return '';
  }

  /// 启动服务
  Future<bool> startService(String sessionId, String workDir, String command) async {
    final inst = getOrCreateInstance(sessionId, workDir);
    if (inst.status == ServiceStatus.running || inst.status == ServiceStatus.starting) {
      return false;
    }

    final trimmedCmd = command.trim();
    if (trimmedCmd.isEmpty) {
      inst.appendLog('启动失败: 未指定启动命令', isError: true);
      notifyListeners();
      return false;
    }

    inst.command = trimmedCmd;
    inst.status = ServiceStatus.starting;
    inst.appendLog('正在启动服务: $trimmedCmd');
    inst.appendLog('工作目录: $workDir');
    notifyListeners();

    try {
      final isWindows = Platform.isWindows;
      final shellExec = isWindows ? 'cmd.exe' : '/bin/bash';
      final shellArgs = isWindows ? ['/c', trimmedCmd] : ['-c', trimmedCmd];

      final process = await Process.start(
        shellExec,
        shellArgs,
        workingDirectory: workDir,
        runInShell: true,
      );

      inst.process = process;
      inst.pid = process.pid;
      inst.startedAt = DateTime.now();
      inst.status = ServiceStatus.running;
      inst.appendLog('服务已就绪，进程标识 PID: ${process.pid}');
      notifyListeners();

      // 监听标准输出流
      inst._stdoutSub = process.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          _handleProcessOutput(inst, text, isError: false);
        },
        onError: (err) {
          inst.appendLog('标准输出流异常: $err', isError: true);
          notifyListeners();
        },
      );

      // 监听错误输出流
      inst._stderrSub = process.stderr.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          _handleProcessOutput(inst, text, isError: true);
        },
        onError: (err) {
          inst.appendLog('错误输出流异常: $err', isError: true);
          notifyListeners();
        },
      );

      // 监听退出
      process.exitCode.then((exitCode) {
        inst.disposeSubscriptions();
        inst.status = ServiceStatus.stopped;
        inst.process = null;
        inst.pid = null;
        inst.appendLog('服务已停止，退出代码: $exitCode', isError: exitCode != 0);
        notifyListeners();
      });

      return true;
    } catch (e) {
      inst.status = ServiceStatus.error;
      inst.process = null;
      inst.pid = null;
      inst.appendLog('服务启动失败: $e', isError: true);
      notifyListeners();
      return false;
    }
  }

  /// 处理进程输出的文本切分
  void _handleProcessOutput(ProjectServiceInstance inst, String chunk, {required bool isError}) {
    final lines = chunk.split(RegExp(r'\r?\n'));
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i == lines.length - 1 && line.isEmpty) continue;
      inst.appendLog(line, isError: isError);
    }
    notifyListeners();
  }

  /// 停止服务
  Future<void> stopService(String sessionId) async {
    final inst = _services[sessionId];
    if (inst == null || inst.process == null) return;

    inst.status = ServiceStatus.stopping;
    inst.appendLog('正在发送终止信号停止服务...');
    notifyListeners();

    try {
      inst.process?.kill(ProcessSignal.sigterm);
      // 延迟 500 毫秒若仍未退出则强杀
      Future.delayed(const Duration(milliseconds: 500), () {
        if (inst.status != ServiceStatus.stopped) {
          inst.process?.kill(ProcessSignal.sigkill);
        }
      });
    } catch (e) {
      inst.appendLog('停止服务发生异常: $e', isError: true);
    }
  }

  /// 重启服务
  Future<void> restartService(String sessionId) async {
    final inst = _services[sessionId];
    if (inst == null) return;

    final cmd = inst.command;
    final workDir = inst.workDir;
    await stopService(sessionId);

    // 等待旧进程完全退出后重新启动
    await Future.delayed(const Duration(milliseconds: 600));
    await startService(sessionId, workDir, cmd);
  }

  /// 清空日志
  void clearLogs(String sessionId) {
    final inst = _services[sessionId];
    if (inst != null) {
      inst.clearLogs();
      notifyListeners();
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/attachment.dart';
import '../models/claude_process_instance.dart';
import '../models/claude_profile.dart';
import '../models/claude_stream_event.dart';
import 'attachment_service.dart';
import 'claude_env_service.dart';
import 'claude_profile_service.dart';
import 'database_service.dart';

/// Claude Code 进程多实例调度管理器
class ClaudeProcessManager {
  static final ClaudeProcessManager instance = ClaudeProcessManager._internal();
  ClaudeProcessManager._internal();

  final DatabaseService _db = DatabaseService.instance;
  final ClaudeEnvService _envService = ClaudeEnvService.instance;
  final ClaudeProfileService _profileService = ClaudeProfileService.instance;
  final AttachmentService _attachmentService = AttachmentService.instance;

  final Map<String, ClaudeProcessInstance> _instances = {};

  /// 获取当前内存中的全部实例
  List<ClaudeProcessInstance> get instances => _instances.values.toList();

  /// 初始化从数据库加载历史活跃实例
  Future<void> initialize() async {
    final list = await _db.loadInstances();
    for (final inst in list) {
      inst.status = ClaudeProcessStatus.idle;
      _instances[inst.id] = inst;
    }
  }

  /// 创建并注册一个新实例
  Future<ClaudeProcessInstance> createInstance({
    required ClaudeProfile profile,
    required String workDir,
    String? sessionId,
  }) async {
    final now = DateTime.now();
    final instanceId = 'inst_${now.millisecondsSinceEpoch}';

    final instance = ClaudeProcessInstance(
      id: instanceId,
      profileId: profile.id,
      workDir: workDir,
      sessionId: sessionId,
      status: ClaudeProcessStatus.idle,
      startedAt: now,
    );

    _instances[instanceId] = instance;
    await _db.saveInstance(instance);
    return instance;
  }

  /// 获取或为指定会话创建绑定且隔离的 Claude Code 实例
  Future<ClaudeProcessInstance> getOrCreateInstanceForSession({
    required String sessionId,
    required ClaudeProfile profile,
    required String workDir,
  }) async {
    final instanceId = 'session_$sessionId';
    final existing = _instances[instanceId];
    if (existing != null) {
      existing.workDir = workDir;
      existing.profileId = profile.id;
      return existing;
    }

    final newInst = ClaudeProcessInstance(
      id: instanceId,
      profileId: profile.id,
      workDir: workDir,
      sessionId: null,
      status: ClaudeProcessStatus.idle,
      startedAt: DateTime.now(),
    );

    _instances[instanceId] = newInst;
    await _db.saveInstance(newInst);
    return newInst;
  }

  /// 以流式模式在指定实例上执行改代码或问答任务
  Stream<ClaudeStreamEvent> executeTask({
    required String instanceId,
    required ClaudeProfile profile,
    required String prompt,
    List<Attachment> attachments = const [],
  }) {
    final controller = StreamController<ClaudeStreamEvent>();

    _runTask(
      instanceId: instanceId,
      profile: profile,
      prompt: prompt,
      attachments: attachments,
      controller: controller,
    );

    return controller.stream;
  }

  /// 内部任务启动与输出流分发处理
  Future<void> _runTask({
    required String instanceId,
    required ClaudeProfile profile,
    required String prompt,
    required List<Attachment> attachments,
    required StreamController<ClaudeStreamEvent> controller,
  }) async {
    final inst = _instances[instanceId];
    if (inst == null) {
      controller.add(const ClaudeStreamEvent(type: 'error', content: '未找到绑定的实例'));
      await controller.close();
      return;
    }

    final envInfo = await _envService.detectEnvironment();
    final execPath = envInfo.executablePath;
    if (execPath == null || execPath.isEmpty) {
      inst.status = ClaudeProcessStatus.error;
      inst.appendLog('未找到 Claude Code 可执行文件路径');
      controller.add(const ClaudeStreamEvent(type: 'error', content: '未检测到 Claude Code 安装路径'));
      await controller.close();
      return;
    }

    inst.status = ClaudeProcessStatus.streaming;
    inst.currentTask = prompt;
    inst.appendLog('> 正在准备执行任务...');

    // 拼接附件
    final finalPrompt = _attachmentService.buildPromptWithAttachments(
      userText: prompt,
      attachments: attachments,
    );

    // 组装命令行参数，必须包含 --verbose 与 stream-json，并跳过非交互模式下的权限拦截
    final args = <String>[
      '-p',
      '--output-format',
      'stream-json',
      '--verbose',
      '--dangerously-skip-permissions',
    ];

    if (inst.sessionId != null && inst.sessionId!.isNotEmpty) {
      args.addAll(['--resume', inst.sessionId!]);
    }

    if (profile.defaultFallbackModel.isNotEmpty) {
      args.addAll(['--model', profile.defaultFallbackModel]);
    }

    args.add(finalPrompt);

    // 组装环境变量
    final env = await _profileService.buildEnvironment(profile);

    Process process;
    try {
      process = await Process.start(
        execPath,
        args,
        workingDirectory: inst.workDir,
        environment: env,
        runInShell: true,
      );
      inst.process = process;
    } catch (e) {
      inst.status = ClaudeProcessStatus.error;
      inst.appendLog('启动进程失败: $e');
      controller.add(ClaudeStreamEvent(type: 'error', content: '启动进程失败: $e'));
      await _db.saveInstance(inst);
      await controller.close();
      return;
    }

    bool hasReceivedContent = false;
    final stderrBuffer = StringBuffer();

    // 监听标准输出
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;

      try {
        final json = jsonDecode(trimmed);
        if (json is Map<String, dynamic>) {
          final event = ClaudeStreamEvent.fromJson(json);
          if (event.sessionId != null && event.sessionId!.isNotEmpty) {
            inst.sessionId = event.sessionId;
          }
          if (event.content != null && event.content!.isNotEmpty) {
            hasReceivedContent = true;
            inst.appendLog(event.content!);
          } else if (event.toolName != null) {
            inst.appendLog('> 正在调用工具: ${event.toolName}');
          }
          controller.add(event);
        }
      } catch (_) {
        inst.appendLog(trimmed);
      }
    });

    // 监听标准错误
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((errLine) {
      final trimmed = errLine.trim();
      if (trimmed.isNotEmpty) {
        stderrBuffer.writeln(trimmed);
        inst.appendLog('[stderr] $trimmed');
      }
    });

    // 监听进程退出
    process.exitCode.then((code) async {
      inst.process = null;
      inst.status = code == 0 ? ClaudeProcessStatus.idle : ClaudeProcessStatus.error;
      inst.appendLog('> 进程执行结束，退出码: $code');
      await _db.saveInstance(inst);

      if (code != 0 && !hasReceivedContent) {
        final errText = stderrBuffer.isNotEmpty ? stderrBuffer.toString() : 'Claude Code 退出，退出码: $code';
        controller.add(ClaudeStreamEvent(type: 'error', content: errText));
      }

      controller.add(const ClaudeStreamEvent(type: 'done'));
      await controller.close();
    });
  }

  /// 终止运行中的实例
  Future<void> killInstance(String instanceId) async {
    final inst = _instances[instanceId];
    if (inst == null) return;

    if (inst.process != null) {
      inst.process!.kill();
      inst.process = null;
    }
    inst.status = ClaudeProcessStatus.terminated;
    inst.appendLog('> 实例已被用户强制终止');
    await _db.saveInstance(inst);
  }

  /// 软删除实例
  Future<void> softDeleteInstance(String instanceId) async {
    await killInstance(instanceId);
    _instances.remove(instanceId);
    await _db.softDeleteInstance(instanceId);
  }
}

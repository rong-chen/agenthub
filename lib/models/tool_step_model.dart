import 'dart:convert';
import 'dart:io';

/// 工具调用步骤执行状态
enum ToolStepStatus {
  running,
  success,
  error,
}

/// 单个工具调用或批量工具调用的步骤数据模型
class ToolStepModel {
  final String id;
  final String toolName;
  final String actionLabel;
  final String target;
  final String? fullPath;
  final String? input;
  String? output;
  ToolStepStatus status;
  final DateTime timestamp;
  final bool isBatch;
  final List<ToolStepModel> subSteps;
  bool isExpanded;

  /// 获取真实的原始 shell 命令
  String get actualCommand {
    if (input != null && input!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(input!);
        if (decoded is Map && decoded['command'] != null) {
          return decoded['command'].toString().trim();
        }
      } catch (_) {
        return input!.trim();
      }
    }
    return target;
  }

  ToolStepModel({
    required this.id,
    required this.toolName,
    required this.actionLabel,
    required this.target,
    this.fullPath,
    this.input,
    this.output,
    this.status = ToolStepStatus.running,
    DateTime? timestamp,
    this.isBatch = false,
    List<ToolStepModel>? subSteps,
    this.isExpanded = false,
  })  : timestamp = timestamp ?? DateTime.now(),
        subSteps = subSteps ?? [];

  /// 从原始 toolName 和 input 创建单步骤
  factory ToolStepModel.fromRaw({
    required String toolName,
    String? input,
    String? output,
    ToolStepStatus status = ToolStepStatus.running,
    String? workDir,
  }) {
    final parsed = parseToolMeta(toolName, input, workDir);
    return ToolStepModel(
      id: 'step_${DateTime.now().microsecondsSinceEpoch}',
      toolName: toolName,
      actionLabel: parsed.actionLabel,
      target: parsed.target,
      fullPath: parsed.fullPath,
      input: input,
      output: output,
      status: status,
    );
  }

  /// 智能解析工具类别和目标参数
  static ({String actionLabel, String target, String? fullPath}) parseToolMeta(
    String toolName,
    String? input, [
    String? workDir,
  ]) {
    String actionLabel = '执行工具';
    String target = '';
    String? fullPath;

    Map<String, dynamic> params = {};
    if (input != null && input.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is Map<String, dynamic>) {
          params = decoded;
        }
      } catch (_) {}
    }

    final lower = toolName.toLowerCase();
    if (lower.contains('bash') || lower.contains('cmd') || lower.contains('exec') || lower.contains('command') || lower == 'ls') {
      actionLabel = '运行命令';
      final cmd = params['command']?.toString() ?? input ?? '';
      target = _formatCommandTarget(cmd);
    } else if (lower.contains('read') || lower.contains('cat') || lower == 'view') {
      actionLabel = '读取文件';
      fullPath = params['file_path']?.toString() ?? params['path']?.toString() ?? input ?? '';
      target = formatDisplayPath(fullPath, workDir);
    } else if (lower.contains('write') || lower.contains('create')) {
      actionLabel = '创建文件';
      fullPath = params['file_path']?.toString() ?? params['path']?.toString() ?? input ?? '';
      target = formatDisplayPath(fullPath, workDir);
    } else if (lower.contains('edit') || lower.contains('patch') || lower.contains('replace') || lower == 'str_replace') {
      actionLabel = '编辑文件';
      fullPath = params['file_path']?.toString() ?? params['path']?.toString() ?? input ?? '';
      target = formatDisplayPath(fullPath, workDir);
    } else if (lower.contains('glob') || lower.contains('find') || lower.contains('search_file')) {
      actionLabel = '查找文件';
      target = params['pattern']?.toString() ?? params['query']?.toString() ?? input ?? '';
    } else if (lower.contains('grep') || lower.contains('search')) {
      actionLabel = '搜索内容';
      target = params['pattern']?.toString() ?? params['query']?.toString() ?? input ?? '';
    } else {
      actionLabel = toolName;
      target = params.isNotEmpty ? params.values.first.toString() : (input ?? '');
    }

    if (target.length > 60) {
      target = '${target.substring(0, 57)}...';
    }

    return (actionLabel: actionLabel, target: target, fullPath: fullPath);
  }

  /// 格式化文件展示路径，统一转换为 ./相对路径 或文件名，杜绝冗长的全局绝对路径
  static String formatDisplayPath(String rawPath, [String? workDir]) {
    var pStr = rawPath.trim();
    if ((pStr.startsWith('"') && pStr.endsWith('"')) || (pStr.startsWith("'") && pStr.endsWith("'"))) {
      pStr = pStr.substring(1, pStr.length - 1).trim();
    }
    if (pStr.isEmpty) return '';

    // 如果已经是相对路径
    if (pStr.startsWith('./')) return pStr;

    final currentDir = workDir ?? Directory.current.path;
    if (pStr.startsWith(currentDir)) {
      pStr = pStr.substring(currentDir.length);
      if (pStr.startsWith('/') || pStr.startsWith('\\')) {
        pStr = pStr.substring(1);
      }
      return './$pStr';
    }

    // 绝对路径根据最后层级简写为 ./相对路径
    if (pStr.startsWith('/')) {
      final parts = pStr.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      if (parts.length > 2) {
        return './${parts.sublist(parts.length - 2).join('/')}';
      } else if (parts.isNotEmpty) {
        return './${parts.last}';
      }
    }

    return './$pStr';
  }

  /// 格式化命令目标描述
  static String _formatCommandTarget(String cmd) {
    final trimmed = cmd.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('ls') || trimmed.startsWith('dir')) {
      return trimmed.contains('-') ? trimmed : '列出项目根目录文件';
    }
    if (trimmed.startsWith('find ') || trimmed.startsWith('locate ')) {
      return '查找配置文件与结构';
    }
    if (trimmed.startsWith('git ')) {
      return trimmed;
    }
    return trimmed;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'toolName': toolName,
        'actionLabel': actionLabel,
        'target': target,
        'fullPath': fullPath,
        'input': input,
        'output': output,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'isBatch': isBatch,
        'subSteps': subSteps.map((s) => s.toJson()).toList(),
      };

  factory ToolStepModel.fromJson(Map<String, dynamic> json) {
    final rawSub = json['subSteps'] as List? ?? [];
    return ToolStepModel(
      id: json['id']?.toString() ?? '',
      toolName: json['toolName']?.toString() ?? '',
      actionLabel: json['actionLabel']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      fullPath: json['fullPath']?.toString(),
      input: json['input']?.toString(),
      output: json['output']?.toString(),
      status: ToolStepStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ToolStepStatus.success,
      ),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isBatch: json['isBatch'] == true,
      subSteps: rawSub
          .map((item) => ToolStepModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

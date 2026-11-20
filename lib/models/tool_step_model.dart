import 'dart:convert';

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
  final String? input;
  String? output;
  ToolStepStatus status;
  final DateTime timestamp;
  final bool isBatch;
  final List<ToolStepModel> subSteps;
  bool isExpanded;

  ToolStepModel({
    required this.id,
    required this.toolName,
    required this.actionLabel,
    required this.target,
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
  }) {
    final parsed = parseToolMeta(toolName, input);
    return ToolStepModel(
      id: 'step_${DateTime.now().microsecondsSinceEpoch}',
      toolName: toolName,
      actionLabel: parsed.actionLabel,
      target: parsed.target,
      input: input,
      output: output,
      status: status,
    );
  }

  /// 智能解析工具类别和目标参数
  static ({String actionLabel, String target}) parseToolMeta(String toolName, String? input) {
    String actionLabel = '执行工具';
    String target = '';

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
    if (lower.contains('bash') || lower.contains('cmd') || lower.contains('exec') || lower.contains('command')) {
      actionLabel = '运行命令';
      final cmd = params['command']?.toString() ?? input ?? '';
      target = _formatCommandTarget(cmd);
    } else if (lower.contains('read') || lower.contains('cat')) {
      actionLabel = '读取文件';
      target = params['file_path']?.toString() ?? params['path']?.toString() ?? input ?? '';
    } else if (lower.contains('write') || lower.contains('create')) {
      actionLabel = '创建文件';
      target = params['file_path']?.toString() ?? params['path']?.toString() ?? input ?? '';
    } else if (lower.contains('edit') || lower.contains('patch') || lower.contains('replace')) {
      actionLabel = '编辑文件';
      target = params['file_path']?.toString() ?? params['path']?.toString() ?? input ?? '';
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

    return (actionLabel: actionLabel, target: target);
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

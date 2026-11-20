import 'dart:convert';
import 'tool_step_model.dart';

/// Claude Code stream-json 模式抛出的事件模型
class ClaudeStreamEvent {
  final String type;
  final String? content;
  final String? toolName;
  final String? toolInput;
  final String? toolOutput;
  final String? sessionId;
  final String? thinking;
  final bool isThinking;
  final double? costUsd;
  final int? durationMs;
  final List<ToolStepModel> toolSteps;

  const ClaudeStreamEvent({
    required this.type,
    this.content,
    this.toolName,
    this.toolInput,
    this.toolOutput,
    this.sessionId,
    this.thinking,
    this.isThinking = false,
    this.costUsd,
    this.durationMs,
    this.toolSteps = const [],
  });

  /// 从 Claude stream-json 行解析事件
  factory ClaudeStreamEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? '';
    final subtype = json['subtype']?.toString() ?? '';
    final sessionId = json['session_id']?.toString();
    final costUsd = (json['total_cost_usd'] as num?)?.toDouble() ?? (json['cost_usd'] as num?)?.toDouble();
    final durationMs = (json['duration_ms'] as num?)?.toInt();

    String? content;
    String? toolName;
    String? toolInput;
    String? toolOutput;
    String? thinking;
    bool isThinking = false;
    final List<ToolStepModel> toolSteps = [];

    if (subtype == 'thinking_tokens') {
      isThinking = true;
    }

    if (type == 'assistant' && json['message'] is Map) {
      final msg = json['message'] as Map;
      final rawContent = msg['content'];
      if (rawContent is List) {
        final buffer = StringBuffer();
        for (final item in rawContent) {
          if (item is Map) {
            final partType = item['type']?.toString();
            if (partType == 'text') {
              buffer.write(item['text'] ?? '');
            } else if (partType == 'thinking') {
              isThinking = true;
              final t = item['thinking']?.toString();
              if (t != null && t.isNotEmpty && t != '...') {
                thinking = t;
              }
            } else if (partType == 'tool_use') {
              final tName = item['name']?.toString() ?? '';
              final tInput = item['input'] != null ? jsonEncode(item['input']) : null;
              toolName = tName;
              toolInput = tInput;
              if (tName.isNotEmpty) {
                toolSteps.add(ToolStepModel.fromRaw(
                  toolName: tName,
                  input: tInput,
                  status: ToolStepStatus.running,
                ));
              }
            }
          }
        }
        if (buffer.isNotEmpty) {
          content = buffer.toString();
        }
      } else if (rawContent is String) {
        content = rawContent;
      }
    } else if (type == 'result') {
      content = json['result']?.toString();
    } else if (type == 'user' && json['message'] is Map) {
      final msg = json['message'] as Map;
      final rawContent = msg['content'];
      if (rawContent is List) {
        for (final item in rawContent) {
          if (item is Map && item['type'] == 'tool_result') {
            toolOutput = item['content']?.toString();
          }
        }
      }
    } else if (type == 'tool_use') {
      toolName = json['name']?.toString() ?? json['tool_name']?.toString();
      toolInput = json['input'] != null ? jsonEncode(json['input']) : null;
      if (toolName != null && toolName.isNotEmpty) {
        toolSteps.add(ToolStepModel.fromRaw(
          toolName: toolName,
          input: toolInput,
          status: ToolStepStatus.running,
        ));
      }
    } else if (type == 'tool_result') {
      toolOutput = json['output']?.toString() ?? json['content']?.toString();
    } else if (type == 'error') {
      content = json['error']?.toString() ?? json['message']?.toString();
    }

    if (toolOutput == null && json['tool_use_result'] is Map) {
      final res = json['tool_use_result'] as Map;
      toolOutput = res['stdout']?.toString() ?? res['content']?.toString();
    }

    return ClaudeStreamEvent(
      type: type,
      content: content,
      toolName: toolName,
      toolInput: toolInput,
      toolOutput: toolOutput,
      sessionId: sessionId,
      thinking: thinking,
      isThinking: isThinking,
      costUsd: costUsd,
      durationMs: durationMs,
      toolSteps: toolSteps,
    );
  }
}

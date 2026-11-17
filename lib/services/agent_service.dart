import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/gateway_config.dart';
import '../models/chat_message_model.dart';
import '../models/skill_model.dart';

/// 对话与 Agent 核心通信服务
class AgentService {
  /// 测试 AgentHub 本地网关连通性
  Future<bool> checkGatewayHealth(int port) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$port/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 发送对话消息并获取完整响应
  Future<String> sendMessage({
    required GatewayConfig config,
    required List<ChatMessageModel> history,
    required List<SkillModel> activeSkills,
    required String userPrompt,
  }) async {
    if (config.apiBaseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
      return '请先在系统设置中配置大模型 API 接口地址与 API Key';
    }

    final base = config.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey.trim()}',
    };

    final systemPrompt = _buildSystemPromptWithSkills(activeSkills);
    final messagesPayload = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final m in history) {
      messagesPayload.add({
        'role': m.role.name,
        'content': m.content,
      });
    }

    messagesPayload.add({
      'role': 'user',
      'content': userPrompt,
    });

    final body = jsonEncode({
      'model': config.modelName.trim().isNotEmpty ? config.modelName.trim() : 'gpt-4o-mini',
      'messages': messagesPayload,
      'stream': false,
    });

    try {
      final response = await http.post(uri, headers: headers, body: body).timeout(
        const Duration(seconds: 60),
      );

      if (response.statusCode != 200) {
        return '上游模型接口响应异常，状态码: ${response.statusCode}';
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map && data.containsKey('choices')) {
        final choices = data['choices'] as List;
        if (choices.isNotEmpty) {
          final first = choices.first;
          final msg = first['message'];
          if (msg is Map && msg.containsKey('content')) {
            return msg['content'].toString();
          }
        }
      }

      return '未能解析上游接口返回的内容';
    } catch (e) {
      return '上游模型接口请求失败: $e';
    }
  }

  /// 流式发送对话消息，实时抛出状态事件与文本片段，支持主动中止
  Stream<Map<String, dynamic>> sendMessageStream({
    required GatewayConfig config,
    required List<ChatMessageModel> history,
    required List<SkillModel> activeSkills,
    required String userPrompt,
    bool Function()? isAborted,
  }) async* {
    yield {'type': 'status', 'text': '正在检索本地可用技能...'};

    if (isAborted?.call() == true) {
      yield {'type': 'aborted'};
      return;
    }

    if (config.apiBaseUrl.trim().isEmpty || config.apiKey.trim().isEmpty) {
      yield {
        'type': 'error',
        'error': '请先在系统设置中配置大模型 API 接口地址与 API Key',
      };
      return;
    }

    final base = config.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');
    final systemPrompt = _buildSystemPromptWithSkills(activeSkills);

    final messagesPayload = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final m in history) {
      messagesPayload.add({
        'role': m.role.name,
        'content': m.content,
      });
    }

    messagesPayload.add({
      'role': 'user',
      'content': userPrompt,
    });

    yield {'type': 'status', 'text': '正在向大模型发起流式请求...'};

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    request.body = jsonEncode({
      'model': config.modelName.trim().isNotEmpty ? config.modelName.trim() : 'gpt-4o-mini',
      'messages': messagesPayload,
      'stream': true,
    });

    http.StreamedResponse streamedResponse;
    try {
      final client = http.Client();
      streamedResponse = await client.send(request);
    } catch (e) {
      yield {'type': 'error', 'error': '上游模型网络请求失败: $e'};
      return;
    }

    if (streamedResponse.statusCode != 200) {
      yield {
        'type': 'error',
        'error': '上游模型响应异常，状态码: ${streamedResponse.statusCode}',
      };
      return;
    }

    yield {'type': 'status', 'text': '大模型开始输出回复...'};

    final fullContentBuffer = StringBuffer();

    await for (final chunk in streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (isAborted?.call() == true) {
        yield {'type': 'aborted'};
        return;
      }

      final trimmed = chunk.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) {
        continue;
      }

      final dataStr = trimmed.substring(5).trim();
      if (dataStr == '[DONE]') {
        break;
      }

      try {
        final parsed = jsonDecode(dataStr) as Map<String, dynamic>;
        final choices = parsed['choices'] as List? ?? [];
        if (choices.isNotEmpty) {
          final first = choices.first as Map<String, dynamic>;
          final delta = first['delta'] as Map<String, dynamic>? ?? {};
          final contentPiece = delta['content']?.toString() ?? '';
          if (contentPiece.isNotEmpty) {
            fullContentBuffer.write(contentPiece);
            yield {'type': 'delta', 'text': contentPiece};
          }
        }
      } catch (_) {
        // 忽略非标准 chunk 格式
      }
    }

    yield {
      'type': 'done',
      'content': fullContentBuffer.toString(),
    };
  }

  /// 构建注入了 AgentHub 本地技能的系统提示词
  String _buildSystemPromptWithSkills(List<SkillModel> activeSkills) {
    final buffer = StringBuffer();
    buffer.writeln('你是由 AgentHub 驱动的桌面后台智能助手。');
    buffer.writeln('你可以参考或调用系统所配置的技能来完成任务。');

    if (activeSkills.isEmpty) {
      return buffer.toString();
    }

    buffer.writeln('\n当前已加载并激活的本地技能列表:');
    for (final skill in activeSkills) {
      buffer.writeln('---');
      buffer.writeln('技能名称: ${skill.name} (版本: ${skill.version})');
      buffer.writeln('技能描述: ${skill.description}');
      buffer.writeln('依赖环境: bins=[${skill.requiredBins.join(', ')}], env=[${skill.requiredEnvs.join(', ')}]');
      buffer.writeln('工作流说明:');
      buffer.writeln(skill.instructions);
    }

    return buffer.toString();
  }
}

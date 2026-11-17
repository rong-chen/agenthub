import 'dart:convert';
import 'dart:io';
import '../models/gateway_config.dart';
import '../models/skill_model.dart';
import '../models/chat_message_model.dart';
import 'skill_service.dart';
import 'agent_service.dart';

/// 网关启动结果对象
class GatewayStartResult {
  final bool isSuccess;
  final String message;

  GatewayStartResult({
    required this.isSuccess,
    required this.message,
  });
}

/// AgentHub 本地内置网关服务，支持 HTTP 接口与 /ws WebSocket 双向长连接
class GatewayServer {
  final SkillService _skillService;
  final AgentService _agentService;
  HttpServer? _server;
  int _port = 18789;
  bool _isRunning = false;
  final List<WebSocket> _activeWebSockets = [];

  GatewayServer({
    required SkillService skillService,
    required AgentService agentService,
  })  : _skillService = skillService,
        _agentService = agentService;

  bool get isRunning => _isRunning;
  int get port => _port;
  int get activeClientsCount => _activeWebSockets.length;

  /// 启动本地网关 HTTP 与 WebSocket 服务，动态绑定配置获取函数
  Future<GatewayStartResult> start({
    required int port,
    required GatewayConfig Function() getConfig,
    required List<SkillModel> Function() getSkills,
  }) async {
    if (_isRunning) {
      return GatewayStartResult(
        isSuccess: true,
        message: '网关已在运行 (http://127.0.0.1:$_port)',
      );
    }

    try {
      _port = port;
      // 绑定本地回环地址
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _port,
        shared: true,
      );
      _isRunning = true;

      _server!.listen(
        (HttpRequest request) {
          _handleHttpRequest(request, getConfig, getSkills);
        },
        onError: (_) {
          _isRunning = false;
        },
      );

      return GatewayStartResult(
        isSuccess: true,
        message: '网关已启动 (http://127.0.0.1:$_port)',
      );
    } on SocketException catch (e) {
      _isRunning = false;
      return GatewayStartResult(
        isSuccess: false,
        message: '端口 $_port 无法监听: ${e.message}',
      );
    } catch (e) {
      _isRunning = false;
      return GatewayStartResult(
        isSuccess: false,
        message: '网关启动异常: $e',
      );
    }
  }

  /// 停止本地网关服务
  Future<void> stop() async {
    if (_server == null) {
      return;
    }

    for (final ws in _activeWebSockets) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _activeWebSockets.clear();

    await _server!.close(force: true);
    _server = null;
    _isRunning = false;
  }

  /// 路由请求分发
  Future<void> _handleHttpRequest(
    HttpRequest request,
    GatewayConfig Function() getConfig,
    List<SkillModel> Function() getSkills,
  ) async {
    final path = request.uri.path;

    // 处理 WebSocket 协议升级请求
    if (path == '/ws') {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleWebSocketConnection(socket, getConfig, getSkills);
        return;
      }
    }

    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Content-Type', 'application/json; charset=utf-8');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (request.method == 'GET' && path == '/health') {
      await _handleHealth(response, getSkills());
      return;
    }

    if (request.method == 'GET' && path == '/v1/models') {
      await _handleModels(response);
      return;
    }

    if (request.method == 'POST' && path == '/v1/chat/completions') {
      await _handleChatCompletions(request, response, getConfig(), getSkills());
      return;
    }

    if (request.method == 'GET' && path == '/api/skills') {
      await _handleGetSkills(response, getSkills());
      return;
    }

    if (request.method == 'POST' && path == '/api/skills/install') {
      await _handleInstallSkill(request, response);
      return;
    }

    response.statusCode = HttpStatus.notFound;
    response.write(jsonEncode({'error': '未找到对应路径'}));
    await response.close();
  }

  /// 处理 WebSocket 双向连接与流式事件
  void _handleWebSocketConnection(
    WebSocket socket,
    GatewayConfig Function() getConfig,
    List<SkillModel> Function() getSkills,
  ) {
    _activeWebSockets.add(socket);
    final Set<String> abortedSessions = {};

    socket.listen(
      (dynamic data) async {
        try {
          final payload = jsonDecode(data.toString()) as Map<String, dynamic>;
          final type = payload['type']?.toString();

          if (type == 'ping') {
            socket.add(jsonEncode({'type': 'pong'}));
            return;
          }

          if (type == 'abort') {
            final sessionId = payload['id']?.toString() ?? '';
            if (sessionId.isNotEmpty) {
              abortedSessions.add(sessionId);
            }
            return;
          }

          if (type == 'chat') {
            final sessionId = payload['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
            final prompt = payload['content']?.toString() ?? '';
            final rawHistory = payload['history'] as List? ?? [];
            final List<ChatMessageModel> history = [];

            for (final item in rawHistory) {
              if (item is! Map) {
                continue;
              }
              final statusStr = item['status']?.toString();
              if (statusStr == 'error') {
                continue;
              }
              final roleStr = item['role']?.toString() ?? 'user';
              final contentStr = item['content']?.toString() ?? '';
              final role = MessageRole.values.firstWhere(
                (e) => e.name == roleStr,
                orElse: () => MessageRole.user,
              );
              history.add(ChatMessageModel(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                role: role,
                content: contentStr,
                timestamp: DateTime.now(),
              ));
            }

            final activeSkills = getSkills().where((s) => s.isEnabled).toList();

            // 实时动态读取最新配置
            final currentConfig = getConfig();

            await for (final event in _agentService.sendMessageStream(
              config: currentConfig,
              history: history,
              activeSkills: activeSkills,
              userPrompt: prompt,
              isAborted: () => abortedSessions.contains(sessionId),
            )) {
              if (socket.readyState != WebSocket.open) {
                break;
              }
              final outEvent = Map<String, dynamic>.from(event);
              outEvent['id'] = sessionId;
              socket.add(jsonEncode(outEvent));
            }

            abortedSessions.remove(sessionId);
          }
        } catch (e) {
          if (socket.readyState == WebSocket.open) {
            socket.add(jsonEncode({
              'type': 'error',
              'error': '解析指令异常: $e',
            }));
          }
        }
      },
      onDone: () {
        _activeWebSockets.remove(socket);
      },
      onError: (_) {
        _activeWebSockets.remove(socket);
      },
    );
  }

  /// 健康检查接口响应
  Future<void> _handleHealth(HttpResponse response, List<SkillModel> skills) async {
    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({
      'status': 'ok',
      'gateway': 'agenthub',
      'port': _port,
      'websocket': 'ws://127.0.0.1:$_port/ws',
      'skills_count': skills.where((s) => s.isEnabled).length,
      'active_ws_clients': _activeWebSockets.length,
    }));
    await response.close();
  }

  /// 模型列表接口响应
  Future<void> _handleModels(HttpResponse response) async {
    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({
      'object': 'list',
      'data': [
        {
          'id': 'agenthub-default',
          'object': 'model',
          'owned_by': 'agenthub',
        }
      ],
    }));
    await response.close();
  }

  /// HTTP 对话补全接口响应
  Future<void> _handleChatCompletions(
    HttpRequest request,
    HttpResponse response,
    GatewayConfig config,
    List<SkillModel> skills,
  ) async {
    try {
      final bodyString = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyString) as Map<String, dynamic>;

      final rawMessages = body['messages'] as List? ?? [];
      final List<ChatMessageModel> history = [];

      for (final item in rawMessages) {
        if (item is! Map) {
          continue;
        }
        final roleStr = item['role']?.toString() ?? 'user';
        final contentStr = item['content']?.toString() ?? '';
        final role = MessageRole.values.firstWhere(
          (e) => e.name == roleStr,
          orElse: () => MessageRole.user,
        );
        history.add(ChatMessageModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: role,
          content: contentStr,
          timestamp: DateTime.now(),
        ));
      }

      final lastUserMessage = history.lastWhere(
        (m) => m.role == MessageRole.user,
        orElse: () => ChatMessageModel(
          id: '0',
          role: MessageRole.user,
          content: '',
          timestamp: DateTime.now(),
        ),
      );

      final activeSkills = skills.where((s) => s.isEnabled).toList();
      final reply = await _agentService.sendMessage(
        config: config,
        history: history.sublist(0, history.length > 1 ? history.length - 1 : 0),
        activeSkills: activeSkills,
        userPrompt: lastUserMessage.content,
      );

      final resultJson = {
        'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
        'object': 'chat.completion',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': config.modelName.isNotEmpty ? config.modelName : 'agenthub-default',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': reply,
            },
            'finish_reason': 'stop',
          }
        ],
      };

      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode(resultJson));
      await response.close();
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(jsonEncode({'error': '处理对话失败: $e'}));
      await response.close();
    }
  }

  /// 获取所有已加载技能
  Future<void> _handleGetSkills(HttpResponse response, List<SkillModel> skills) async {
    final list = skills.map((s) => s.toJson()).toList();
    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({'data': list}));
    await response.close();
  }

  /// 接口触发技能安装
  Future<void> _handleInstallSkill(HttpRequest request, HttpResponse response) async {
    try {
      final bodyString = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyString) as Map<String, dynamic>;
      final source = body['source']?.toString() ?? '';

      final message = await _skillService.installSkill(source: source);
      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode({'message': message}));
      await response.close();
    } catch (e) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': '安装请求解析失败: $e'}));
      await response.close();
    }
  }
}

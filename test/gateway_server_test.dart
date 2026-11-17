import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:agenthub/models/gateway_config.dart';
import 'package:agenthub/services/skill_service.dart';
import 'package:agenthub/services/agent_service.dart';
import 'package:agenthub/services/gateway_server.dart';

void main() {
  test('验证 AgentHub 本地内置网关服务 (HTTP 与 /ws WebSocket)', () async {
    final skillService = SkillService();
    final agentService = AgentService();
    final config = GatewayConfig.initial();

    final server = GatewayServer(
      skillService: skillService,
      agentService: agentService,
    );

    final skills = await skillService.loadAllSkills();
    final result = await server.start(
      port: 19789,
      getConfig: () => config,
      getSkills: () => skills,
    );

    expect(result.isSuccess, true);
    expect(server.isRunning, true);

    // 1. 测试 HTTP 健康检查接口
    final healthResp = await http.get(Uri.parse('http://127.0.0.1:19789/health'));
    expect(healthResp.statusCode, 200);
    final healthData = jsonDecode(healthResp.body) as Map<String, dynamic>;
    expect(healthData['status'], 'ok');
    expect(healthData['gateway'], 'agenthub');
    expect(healthData['websocket'], 'ws://127.0.0.1:19789/ws');

    // 2. 测试 HTTP 技能列表接口
    final skillsResp = await http.get(Uri.parse('http://127.0.0.1:19789/api/skills'));
    expect(skillsResp.statusCode, 200);
    final skillsData = jsonDecode(skillsResp.body) as Map<String, dynamic>;
    expect(skillsData['data'], isA<List>());

    // 3. 测试 /ws WebSocket 双向长连接
    final ws = await WebSocket.connect('ws://127.0.0.1:19789/ws');
    expect(server.activeClientsCount, 1);

    // 发送 ping
    ws.add(jsonEncode({'type': 'ping'}));
    final replyStr = await ws.first;
    final reply = jsonDecode(replyStr.toString()) as Map<String, dynamic>;
    expect(reply['type'], 'pong');

    await ws.close();
    await Future.delayed(const Duration(milliseconds: 100));
    expect(server.activeClientsCount, 0);

    // 关闭服务
    await server.stop();
    expect(server.isRunning, false);
  });
}

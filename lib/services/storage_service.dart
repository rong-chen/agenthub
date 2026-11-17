import 'dart:convert';
import 'dart:io';
import '../models/gateway_config.dart';
import '../models/chat_message_model.dart';
import '../utils/path_utils.dart';

/// 本地文件持久化存储服务 (~/.agenthub)
class StorageService {
  String get _baseDir => PathUtils.agentHubRootDir;

  File get _configFile => File('$_baseDir/config.json');
  File get _historyFile => File('$_baseDir/history.json');

  /// 保存网关与运行配置
  Future<void> saveConfig(GatewayConfig config) async {
    final jsonStr = jsonEncode(config.toJson());
    await _configFile.writeAsString(jsonStr);
  }

  /// 读取网关与运行配置
  Future<GatewayConfig> loadConfig() async {
    if (!_configFile.existsSync()) {
      return GatewayConfig.initial();
    }

    try {
      final jsonStr = await _configFile.readAsString();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return GatewayConfig.fromJson(map);
    } catch (_) {
      return GatewayConfig.initial();
    }
  }

  /// 保存消息历史
  Future<void> saveMessages(List<ChatMessageModel> messages) async {
    final list = messages.map((m) => m.toJson()).toList();
    await _historyFile.writeAsString(jsonEncode(list));
  }

  /// 加载消息历史
  Future<List<ChatMessageModel>> loadMessages() async {
    if (!_historyFile.existsSync()) {
      return [];
    }

    try {
      final jsonStr = await _historyFile.readAsString();
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((item) => ChatMessageModel.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 清空消息历史
  Future<void> clearMessages() async {
    if (_historyFile.existsSync()) {
      await _historyFile.delete();
    }
  }
}

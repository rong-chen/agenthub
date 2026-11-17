/// 本地网关与核心配置模型
class GatewayConfig {
  int gatewayPort;
  bool autoStartGateway;
  String apiBaseUrl;
  String apiKey;
  String modelName;
  String customSkillsPath;
  bool minimizeToTrayOnClose;
  String themeMode; // light | dark

  GatewayConfig({
    required this.gatewayPort,
    required this.autoStartGateway,
    required this.apiBaseUrl,
    required this.apiKey,
    required this.modelName,
    required this.customSkillsPath,
    required this.minimizeToTrayOnClose,
    this.themeMode = 'light',
  });

  /// 创建初始配置
  factory GatewayConfig.initial() {
    return GatewayConfig(
      gatewayPort: 18789,
      autoStartGateway: true,
      apiBaseUrl: '',
      apiKey: '',
      modelName: '',
      customSkillsPath: '',
      minimizeToTrayOnClose: true,
      themeMode: 'light',
    );
  }

  /// 转换为 JSON 格式
  Map<String, dynamic> toJson() {
    return {
      'gatewayPort': gatewayPort,
      'autoStartGateway': autoStartGateway,
      'apiBaseUrl': apiBaseUrl,
      'apiKey': apiKey,
      'modelName': modelName,
      'customSkillsPath': customSkillsPath,
      'minimizeToTrayOnClose': minimizeToTrayOnClose,
      'themeMode': themeMode,
    };
  }

  /// 从 JSON 读取配置
  factory GatewayConfig.fromJson(Map<String, dynamic> json) {
    return GatewayConfig(
      gatewayPort: json['gatewayPort'] is int ? json['gatewayPort'] as int : 18789,
      autoStartGateway: json['autoStartGateway'] != false,
      apiBaseUrl: json['apiBaseUrl']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ?? '',
      modelName: json['modelName']?.toString() ?? '',
      customSkillsPath: json['customSkillsPath']?.toString() ?? '',
      minimizeToTrayOnClose: json['minimizeToTrayOnClose'] != false,
      themeMode: json['themeMode']?.toString() == 'dark' ? 'dark' : 'light',
    );
  }
}

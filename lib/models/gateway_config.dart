import '../config/app_env.dart';

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
  String httpProxy; // 网络代理地址
  double temperature; // 模型温度
  double topP; // Top_P采样
  bool wechatChannelEnabled; // 是否开启微信通道
  bool wechatAutoReply; // 是否开启微信自动回复

  GatewayConfig({
    required this.gatewayPort,
    required this.autoStartGateway,
    required this.apiBaseUrl,
    required this.apiKey,
    required this.modelName,
    required this.customSkillsPath,
    required this.minimizeToTrayOnClose,
    this.themeMode = 'light',
    this.httpProxy = '',
    this.temperature = 0.7,
    this.topP = 0.9,
    this.wechatChannelEnabled = false,
    this.wechatAutoReply = false,
  });

  /// 创建初始配置
  factory GatewayConfig.initial() {
    return GatewayConfig(
      gatewayPort: AppEnv.defaultGatewayPort,
      autoStartGateway: true,
      apiBaseUrl: '',
      apiKey: '',
      modelName: '',
      customSkillsPath: '',
      minimizeToTrayOnClose: true,
      themeMode: 'light',
      httpProxy: '',
      temperature: 0.7,
      topP: 0.9,
      wechatChannelEnabled: false,
      wechatAutoReply: false,
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
      'httpProxy': httpProxy,
      'temperature': temperature,
      'topP': topP,
      'wechatChannelEnabled': wechatChannelEnabled,
      'wechatAutoReply': wechatAutoReply,
    };
  }

  /// 复制并更新部分属性
  GatewayConfig copyWith({
    int? gatewayPort,
    bool? autoStartGateway,
    String? apiBaseUrl,
    String? apiKey,
    String? modelName,
    String? customSkillsPath,
    bool? minimizeToTrayOnClose,
    String? themeMode,
    String? httpProxy,
    double? temperature,
    double? topP,
    bool? wechatChannelEnabled,
    bool? wechatAutoReply,
  }) {
    return GatewayConfig(
      gatewayPort: gatewayPort ?? this.gatewayPort,
      autoStartGateway: autoStartGateway ?? this.autoStartGateway,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      customSkillsPath: customSkillsPath ?? this.customSkillsPath,
      minimizeToTrayOnClose: minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      themeMode: themeMode ?? this.themeMode,
      httpProxy: httpProxy ?? this.httpProxy,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      wechatChannelEnabled: wechatChannelEnabled ?? this.wechatChannelEnabled,
      wechatAutoReply: wechatAutoReply ?? this.wechatAutoReply,
    );
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
      httpProxy: json['httpProxy']?.toString() ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      wechatChannelEnabled: json['wechatChannelEnabled'] == true,
      wechatAutoReply: json['wechatAutoReply'] == true,
    );
  }
}

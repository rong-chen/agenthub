import 'dart:convert';

/// Claude 模型角色映射配置
class ClaudeModelRoleMapping {
  String displayName;
  String actualModel;
  bool is1M;

  ClaudeModelRoleMapping({
    this.displayName = '',
    this.actualModel = '',
    this.is1M = false,
  });

  Map<String, dynamic> toMap() => {
    'display_name': displayName,
    'actual_model': actualModel,
    'is_1m': is1M,
  };

  factory ClaudeModelRoleMapping.fromMap(Map<String, dynamic>? map) {
    if (map == null) return ClaudeModelRoleMapping();
    return ClaudeModelRoleMapping(
      displayName: map['display_name']?.toString() ?? '',
      actualModel: map['actual_model']?.toString() ?? '',
      is1M: map['is_1m'] == true,
    );
  }
}

/// Claude Code Profile 配置模型
class ClaudeProfile {
  final String id;
  String name; // 供应商名称
  String remark; // 备注
  String websiteUrl; // 官网链接
  String authType; // oauth | api_key
  String? apiKeyRef;
  String apiBaseUrl; // 兼容 Claude API 的服务请求地址
  String apiFormat; // Anthropic Messages(原生)
  String authField; // ANTHROPIC_AUTH_TOKEN | ANTHROPIC_API_KEY

  // 模型映射
  ClaudeModelRoleMapping sonnetMapping;
  ClaudeModelRoleMapping opusMapping;
  ClaudeModelRoleMapping fableMapping;
  ClaudeModelRoleMapping haikuMapping;

  String defaultFallbackModel; // 默认兜底模型
  String userAgent; // 自定义 User-Agent

  // 快捷配置开关
  bool hideCoAuthoredBy; // 隐藏 AI 署名
  bool disableNonEssentialTraffic; // 禁用非必要流量
  bool disableAutoUpdate; // 禁用自动升级
  bool enableToolSearch; // 启用 Tool Search
  bool maxThinking; // 最大强度思考
  bool teammatesMode; // Teammates 模式

  String configDir;
  String? extraSettingsJson; // 附加配置 JSON 片段
  DateTime createdAt;
  DateTime lastUsedAt;

  ClaudeProfile({
    required this.id,
    required this.name,
    this.remark = '',
    this.websiteUrl = '',
    this.authType = 'oauth',
    this.apiKeyRef,
    this.apiBaseUrl = '',
    this.apiFormat = 'Anthropic Messages(原生)',
    this.authField = 'ANTHROPIC_AUTH_TOKEN',
    ClaudeModelRoleMapping? sonnetMapping,
    ClaudeModelRoleMapping? opusMapping,
    ClaudeModelRoleMapping? fableMapping,
    ClaudeModelRoleMapping? haikuMapping,
    this.defaultFallbackModel = '',
    this.userAgent = '',
    this.hideCoAuthoredBy = false,
    this.disableNonEssentialTraffic = true,
    this.disableAutoUpdate = false,
    this.enableToolSearch = false,
    this.maxThinking = false,
    this.teammatesMode = false,
    required this.configDir,
    this.extraSettingsJson,
    required this.createdAt,
    required this.lastUsedAt,
  })  : sonnetMapping = sonnetMapping ?? ClaudeModelRoleMapping(),
        opusMapping = opusMapping ?? ClaudeModelRoleMapping(),
        fableMapping = fableMapping ?? ClaudeModelRoleMapping(),
        haikuMapping = haikuMapping ?? ClaudeModelRoleMapping();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'remark': remark,
      'website_url': websiteUrl,
      'auth_type': authType,
      'api_key_ref': apiKeyRef,
      'api_base_url': apiBaseUrl,
      'api_format': apiFormat,
      'auth_field': authField,
      'sonnet_mapping': jsonEncode(sonnetMapping.toMap()),
      'opus_mapping': jsonEncode(opusMapping.toMap()),
      'fable_mapping': jsonEncode(fableMapping.toMap()),
      'haiku_mapping': jsonEncode(haikuMapping.toMap()),
      'default_fallback_model': defaultFallbackModel,
      'user_agent': userAgent,
      'hide_co_authored_by': hideCoAuthoredBy ? 1 : 0,
      'disable_non_essential_traffic': disableNonEssentialTraffic ? 1 : 0,
      'disable_auto_update': disableAutoUpdate ? 1 : 0,
      'enable_tool_search': enableToolSearch ? 1 : 0,
      'max_thinking': maxThinking ? 1 : 0,
      'teammates_mode': teammatesMode ? 1 : 0,
      'config_dir': configDir,
      'extra_settings_json': extraSettingsJson,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_used_at': lastUsedAt.millisecondsSinceEpoch,
    };
  }

  factory ClaudeProfile.fromMap(Map<String, dynamic> map) {
    ClaudeModelRoleMapping parseMapping(String key) {
      if (map[key] != null) {
        try {
          final decoded = jsonDecode(map[key] as String);
          if (decoded is Map<String, dynamic>) {
            return ClaudeModelRoleMapping.fromMap(decoded);
          }
        } catch (_) {}
      }
      return ClaudeModelRoleMapping();
    }

    return ClaudeProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      remark: map['remark']?.toString() ?? '',
      websiteUrl: map['website_url']?.toString() ?? '',
      authType: map['auth_type'] as String? ?? 'oauth',
      apiKeyRef: map['api_key_ref'] as String?,
      apiBaseUrl: map['api_base_url']?.toString() ?? '',
      apiFormat: map['api_format']?.toString() ?? 'Anthropic Messages(原生)',
      authField: map['auth_field']?.toString() ?? 'ANTHROPIC_AUTH_TOKEN',
      sonnetMapping: parseMapping('sonnet_mapping'),
      opusMapping: parseMapping('opus_mapping'),
      fableMapping: parseMapping('fable_mapping'),
      haikuMapping: parseMapping('haiku_mapping'),
      defaultFallbackModel: map['default_fallback_model']?.toString() ?? '',
      userAgent: map['user_agent']?.toString() ?? '',
      hideCoAuthoredBy: (map['hide_co_authored_by'] as int?) == 1,
      disableNonEssentialTraffic: (map['disable_non_essential_traffic'] as int?) != 0,
      disableAutoUpdate: (map['disable_auto_update'] as int?) == 1,
      enableToolSearch: (map['enable_tool_search'] as int?) == 1,
      maxThinking: (map['max_thinking'] as int?) == 1,
      teammatesMode: (map['teammates_mode'] as int?) == 1,
      configDir: map['config_dir'] as String,
      extraSettingsJson: map['extra_settings_json'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastUsedAt: DateTime.fromMillisecondsSinceEpoch(map['last_used_at'] as int),
    );
  }

  /// 生成标准的 Claude Code settings.json 字典
  Map<String, dynamic> generateSettingsJson(String? apiKey) {
    final env = <String, String>{};

    if (apiBaseUrl.trim().isNotEmpty) {
      env['ANTHROPIC_BASE_URL'] = apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }

    if (apiKey != null && apiKey.trim().isNotEmpty) {
      env[authField] = apiKey.trim();
    }

    // 映射 Sonnet
    if (sonnetMapping.actualModel.isNotEmpty) {
      final suffix = sonnetMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = '${sonnetMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_SONNET_MODEL_NAME'] = sonnetMapping.displayName.isNotEmpty
          ? sonnetMapping.displayName
          : sonnetMapping.actualModel;
    }

    // 映射 Opus
    if (opusMapping.actualModel.isNotEmpty) {
      final suffix = opusMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = '${opusMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_OPUS_MODEL_NAME'] = opusMapping.displayName.isNotEmpty
          ? opusMapping.displayName
          : opusMapping.actualModel;
    }

    // 映射 Fable
    if (fableMapping.actualModel.isNotEmpty) {
      final suffix = fableMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_FABLE_MODEL'] = '${fableMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_FABLE_MODEL_NAME'] = fableMapping.displayName.isNotEmpty
          ? fableMapping.displayName
          : fableMapping.actualModel;
    }

    // 映射 Haiku
    if (haikuMapping.actualModel.isNotEmpty) {
      final suffix = haikuMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = '${haikuMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME'] = haikuMapping.displayName.isNotEmpty
          ? haikuMapping.displayName
          : haikuMapping.actualModel;
    }

    if (disableNonEssentialTraffic) {
      env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1';
    }

    if (disableAutoUpdate) {
      env['DISABLE_AUTO_UPDATE'] = '1';
    }

    if (maxThinking) {
      env['MAX_THINKING_TOKENS'] = '31999';
    }

    if (teammatesMode) {
      env['TEAMMATES_MODE'] = '1';
    }

    if (enableToolSearch) {
      env['ENABLE_TOOL_SEARCH'] = '1';
    }

    final root = <String, dynamic>{
      'env': env,
      'includeCoAuthoredBy': !hideCoAuthoredBy,
      'enableToolSearch': enableToolSearch,
      'alwaysThinkingEnabled': maxThinking,
      'teammates': teammatesMode,
    };

    if (extraSettingsJson != null && extraSettingsJson!.trim().isNotEmpty) {
      try {
        final extra = jsonDecode(extraSettingsJson!) as Map<String, dynamic>;
        extra.forEach((k, v) {
          if (k != 'env' && k != 'includeCoAuthoredBy') {
            root[k] = v;
          }
        });
      } catch (_) {}
    }

    return root;
  }
}

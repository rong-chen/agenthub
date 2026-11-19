import 'dart:convert';
import 'dart:io';
import '../models/claude_profile.dart';
import '../utils/path_utils.dart';
import 'credential_service.dart';
import 'database_service.dart';

/// Claude Profile 配置管理服务
class ClaudeProfileService {
  static final ClaudeProfileService instance = ClaudeProfileService._internal();
  ClaudeProfileService._internal();

  final DatabaseService _db = DatabaseService.instance;
  final CredentialService _credential = CredentialService.instance;

  /// Profile 独立配置根目录
  String get _profilesBaseDir => '${PathUtils.agentHubRootDir}/claude_profiles';

  /// 读取所有 Profile
  Future<List<ClaudeProfile>> loadProfiles() async {
    return await _db.loadProfiles();
  }

  /// 创建新 Profile
  Future<ClaudeProfile> createProfile({
    required String name,
    String remark = '',
    String websiteUrl = '',
    String authType = 'api_key',
    String? apiKey,
    String apiBaseUrl = '',
    String apiFormat = 'Anthropic Messages(原生)',
    String authField = 'ANTHROPIC_AUTH_TOKEN',
    ClaudeModelRoleMapping? sonnetMapping,
    ClaudeModelRoleMapping? opusMapping,
    ClaudeModelRoleMapping? fableMapping,
    ClaudeModelRoleMapping? haikuMapping,
    String defaultFallbackModel = '',
    String userAgent = '',
    bool hideCoAuthoredBy = false,
    bool disableNonEssentialTraffic = true,
    bool disableAutoUpdate = false,
    bool enableToolSearch = false,
    bool maxThinking = false,
    bool teammatesMode = false,
    String? extraSettingsJson,
  }) async {
    final now = DateTime.now();
    final id = 'prof_${now.millisecondsSinceEpoch}';
    final profileDir = '$_profilesBaseDir/$id';

    // 创建专属配置文件夹
    final dir = Directory(profileDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    String? apiKeyRef;
    if (authType == 'api_key' && apiKey != null && apiKey.trim().isNotEmpty) {
      apiKeyRef = id;
      await _credential.saveProfileApiKey(id, apiKey.trim());
    }

    final profile = ClaudeProfile(
      id: id,
      name: name.trim(),
      remark: remark.trim(),
      websiteUrl: websiteUrl.trim(),
      authType: authType,
      apiKeyRef: apiKeyRef,
      apiBaseUrl: apiBaseUrl.trim(),
      apiFormat: apiFormat,
      authField: authField,
      sonnetMapping: sonnetMapping,
      opusMapping: opusMapping,
      fableMapping: fableMapping,
      haikuMapping: haikuMapping,
      defaultFallbackModel: defaultFallbackModel.trim(),
      userAgent: userAgent.trim(),
      hideCoAuthoredBy: hideCoAuthoredBy,
      disableNonEssentialTraffic: disableNonEssentialTraffic,
      disableAutoUpdate: disableAutoUpdate,
      enableToolSearch: enableToolSearch,
      maxThinking: maxThinking,
      teammatesMode: teammatesMode,
      configDir: profileDir,
      extraSettingsJson: extraSettingsJson,
      createdAt: now,
      lastUsedAt: now,
    );

    await _db.saveProfile(profile);
    await syncSettingsFile(profile, apiKey);
    return profile;
  }

  /// 更新 Profile
  Future<void> updateProfile({
    required ClaudeProfile profile,
    String? newApiKey,
  }) async {
    profile.lastUsedAt = DateTime.now();

    if (profile.authType == 'api_key' && newApiKey != null && newApiKey.trim().isNotEmpty) {
      profile.apiKeyRef = profile.id;
      await _credential.saveProfileApiKey(profile.id, newApiKey.trim());
    }

    final key = await getProfileApiKey(profile);
    await _db.saveProfile(profile);
    await syncSettingsFile(profile, key);
  }

  /// 删除 Profile
  Future<void> deleteProfile(String profileId) async {
    await _db.deleteProfile(profileId);
    await _credential.deleteProfileApiKey(profileId);

    final dir = Directory('$_profilesBaseDir/$profileId');
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 读取 Profile 的 API Key
  Future<String?> getProfileApiKey(ClaudeProfile profile) async {
    if (profile.apiKeyRef == null || profile.apiKeyRef!.isEmpty) {
      return null;
    }
    return await _credential.readProfileApiKey(profile.apiKeyRef!);
  }

  /// 将配置同步写入该 Profile 专用目录下的 settings.json
  Future<void> syncSettingsFile(ClaudeProfile profile, [String? apiKey]) async {
    try {
      final key = apiKey ?? await getProfileApiKey(profile);
      final jsonMap = profile.generateSettingsJson(key);
      final dir = Directory(profile.configDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File('${profile.configDir}/settings.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonMap));
    } catch (_) {}
  }

  /// 为指定 Profile 组装子进程环境变量
  Future<Map<String, String>> buildEnvironment(ClaudeProfile profile) async {
    final env = Map<String, String>.from(Platform.environment);

    // 隔离配置目录
    env['CLAUDE_CONFIG_DIR'] = profile.configDir;

    // 提取并写入 settings.json
    final key = await getProfileApiKey(profile);
    await syncSettingsFile(profile, key);

    // 注入网络地址与认证字段
    if (profile.apiBaseUrl.trim().isNotEmpty) {
      env['ANTHROPIC_BASE_URL'] = profile.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }

    if (key != null && key.isNotEmpty) {
      env[profile.authField] = key;
      // 同时注入标准 KEY 作为兜底
      env['ANTHROPIC_API_KEY'] = key;
    }

    // 注入模型映射变量
    if (profile.sonnetMapping.actualModel.isNotEmpty) {
      final suffix = profile.sonnetMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = '${profile.sonnetMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_SONNET_MODEL_NAME'] = profile.sonnetMapping.displayName.isNotEmpty
          ? profile.sonnetMapping.displayName
          : profile.sonnetMapping.actualModel;
    }

    if (profile.opusMapping.actualModel.isNotEmpty) {
      final suffix = profile.opusMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = '${profile.opusMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_OPUS_MODEL_NAME'] = profile.opusMapping.displayName.isNotEmpty
          ? profile.opusMapping.displayName
          : profile.opusMapping.actualModel;
    }

    if (profile.fableMapping.actualModel.isNotEmpty) {
      final suffix = profile.fableMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_FABLE_MODEL'] = '${profile.fableMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_FABLE_MODEL_NAME'] = profile.fableMapping.displayName.isNotEmpty
          ? profile.fableMapping.displayName
          : profile.fableMapping.actualModel;
    }

    if (profile.haikuMapping.actualModel.isNotEmpty) {
      final suffix = profile.haikuMapping.is1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = '${profile.haikuMapping.actualModel}$suffix';
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME'] = profile.haikuMapping.displayName.isNotEmpty
          ? profile.haikuMapping.displayName
          : profile.haikuMapping.actualModel;
    }

    if (profile.disableNonEssentialTraffic) {
      env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1';
    }

    if (profile.disableAutoUpdate) {
      env['DISABLE_AUTO_UPDATE'] = '1';
    }

    if (profile.maxThinking) {
      env['MAX_THINKING_TOKENS'] = '31999';
    }

    if (profile.teammatesMode) {
      env['TEAMMATES_MODE'] = '1';
    }

    if (profile.enableToolSearch) {
      env['ENABLE_TOOL_SEARCH'] = '1';
    }

    return env;
  }
}

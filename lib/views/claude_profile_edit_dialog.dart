import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/claude_profile.dart';
import '../services/claude_profile_service.dart';
import '../theme/agenthub_theme.dart';
import '../widgets/app_text_field.dart';

/// Claude 供应商 Profile 编辑与新建抽屉弹窗
class ClaudeProfileEditDialog extends StatefulWidget {
  final ClaudeProfile? profile;

  const ClaudeProfileEditDialog({super.key, this.profile});

  static Future<ClaudeProfile?> show(BuildContext context, {ClaudeProfile? profile}) {
    return showDialog<ClaudeProfile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ClaudeProfileEditDialog(profile: profile),
    );
  }

  @override
  State<ClaudeProfileEditDialog> createState() => _ClaudeProfileEditDialogState();
}

class _ClaudeProfileEditDialogState extends State<ClaudeProfileEditDialog> {
  final _profileService = ClaudeProfileService.instance;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _remarkCtrl;
  late final TextEditingController _websiteCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _apiBaseUrlCtrl;
  late final TextEditingController _fallbackModelCtrl;
  late final TextEditingController _userAgentCtrl;

  late final TextEditingController _sonnetDisplayCtrl;
  late final TextEditingController _sonnetActualCtrl;
  bool _sonnet1M = false;

  late final TextEditingController _opusDisplayCtrl;
  late final TextEditingController _opusActualCtrl;
  bool _opus1M = false;

  late final TextEditingController _fableDisplayCtrl;
  late final TextEditingController _fableActualCtrl;
  bool _fable1M = false;

  late final TextEditingController _haikuDisplayCtrl;
  late final TextEditingController _haikuActualCtrl;
  bool _haiku1M = false;

  bool _obscureApiKey = true;
  bool _showAdvanced = true;
  String _apiFormat = 'Anthropic Messages(原生)';
  String _authField = 'ANTHROPIC_AUTH_TOKEN';

  // 快捷配置选项
  bool _hideCoAuthoredBy = false;
  bool _teammatesMode = false;
  bool _enableToolSearch = false;
  bool _maxThinking = false;
  bool _disableAutoUpdate = false;
  bool _disableNonEssentialTraffic = true;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;

    _nameCtrl = AppTextEditingController(text: p?.name ?? '');
    _remarkCtrl = AppTextEditingController(text: p?.remark ?? '');
    _websiteCtrl = AppTextEditingController(text: p?.websiteUrl ?? '');
    _apiKeyCtrl = AppTextEditingController();
    _apiBaseUrlCtrl = AppTextEditingController(text: p?.apiBaseUrl ?? '');
    _fallbackModelCtrl = AppTextEditingController(text: p?.defaultFallbackModel ?? '');
    _userAgentCtrl = AppTextEditingController(text: p?.userAgent ?? '');

    _sonnetDisplayCtrl = AppTextEditingController(text: p?.sonnetMapping.displayName ?? '');
    _sonnetActualCtrl = AppTextEditingController(text: p?.sonnetMapping.actualModel ?? '');
    _sonnet1M = p?.sonnetMapping.is1M ?? false;

    _opusDisplayCtrl = AppTextEditingController(text: p?.opusMapping.displayName ?? '');
    _opusActualCtrl = AppTextEditingController(text: p?.opusMapping.actualModel ?? '');
    _opus1M = p?.opusMapping.is1M ?? false;

    _fableDisplayCtrl = AppTextEditingController(text: p?.fableMapping.displayName ?? '');
    _fableActualCtrl = AppTextEditingController(text: p?.fableMapping.actualModel ?? '');
    _fable1M = p?.fableMapping.is1M ?? false;

    _haikuDisplayCtrl = AppTextEditingController(text: p?.haikuMapping.displayName ?? '');
    _haikuActualCtrl = AppTextEditingController(text: p?.haikuMapping.actualModel ?? '');
    _haiku1M = p?.haikuMapping.is1M ?? false;

    if (p != null) {
      _apiFormat = p.apiFormat;
      _authField = p.authField;
      _hideCoAuthoredBy = p.hideCoAuthoredBy;
      _teammatesMode = p.teammatesMode;
      _enableToolSearch = p.enableToolSearch;
      _maxThinking = p.maxThinking;
      _disableAutoUpdate = p.disableAutoUpdate;
      _disableNonEssentialTraffic = p.disableNonEssentialTraffic;
      _loadExistingApiKey(p);
    }
  }

  Future<void> _loadExistingApiKey(ClaudeProfile p) async {
    final key = await _profileService.getProfileApiKey(p);
    if (mounted && key != null) {
      setState(() {
        _apiKeyCtrl.text = key;
      });
    }
  }

  List<String> _remoteModels = [];
  bool _isFetchingModels = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    _websiteCtrl.dispose();
    _apiKeyCtrl.dispose();
    _apiBaseUrlCtrl.dispose();
    _fallbackModelCtrl.dispose();
    _userAgentCtrl.dispose();
    _sonnetDisplayCtrl.dispose();
    _sonnetActualCtrl.dispose();
    _opusDisplayCtrl.dispose();
    _opusActualCtrl.dispose();
    _fableDisplayCtrl.dispose();
    _fableActualCtrl.dispose();
    _haikuDisplayCtrl.dispose();
    _haikuActualCtrl.dispose();
    super.dispose();
  }

  /// 从后端拉取模型列表
  Future<void> _fetchModelsFromBackend() async {
    final baseUrl = _apiBaseUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写请求地址')),
      );
      return;
    }

    final cleanUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请求地址格式不正确')),
      );
      return;
    }

    setState(() => _isFetchingModels = true);

    try {
      final candidates = <String>[];
      if (cleanUrl.endsWith('/v1')) {
        candidates.add('$cleanUrl/models');
      } else {
        if (cleanUrl.endsWith('/anthropic') || uri.path.isNotEmpty) {
          candidates.add('${uri.origin}/v1/models');
        }
        candidates.add('$cleanUrl/v1/models');
        candidates.add('$cleanUrl/models');
        if (uri.origin != cleanUrl) {
          candidates.add('${uri.origin}/models');
        }
      }
      final targetUrls = candidates.toSet().toList();

      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'claude-code/0.2.29',
      };
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
      }

      http.Response? lastResponse;
      final List<String> list = [];

      for (final targetUrl in targetUrls) {
        try {
          final res = await http.get(Uri.parse(targetUrl), headers: headers).timeout(const Duration(seconds: 6));
          lastResponse = res;
          if (res.statusCode == 200) {
            final dynamic data = jsonDecode(utf8.decode(res.bodyBytes));
            final dynamic rawList = data is Map ? (data['data'] ?? data['models']) : data;
            if (rawList is List) {
              for (final item in rawList) {
                if (item is Map && item['id'] != null) {
                  list.add(item['id'].toString());
                } else if (item is String) {
                  list.add(item);
                }
              }
            }
            if (list.isNotEmpty) {
              break;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      if (list.isNotEmpty) {
        setState(() {
          _remoteModels = list;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功从后端拉取 ${list.length} 个模型')),
        );
        _autoPresetModels();
      } else if (lastResponse != null) {
        if (lastResponse.statusCode == 401 || lastResponse.statusCode == 403) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('鉴权失败，请检查 API Key 是否正确')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('拉取模型失败，HTTP 状态码: ${lastResponse.statusCode}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能连接到模型接口，请检查请求地址和网络')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接后端拉取模型失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isFetchingModels = false);
      }
    }
  }

  /// 一键预设：根据从后端拉取的真实可用模型匹配填入
  void _autoPresetModels() {
    if (_remoteModels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点击获取模型列表，从后端拉取真实可用模型')),
      );
      return;
    }

    String findModel(List<String> keywords) {
      for (final kw in keywords) {
        final found = _remoteModels.firstWhere(
          (m) => m.toLowerCase().contains(kw.toLowerCase()),
          orElse: () => '',
        );
        if (found.isNotEmpty) return found;
      }
      return '';
    }

    final defaultModel = _remoteModels.first;
    final sonnet = findModel(['sonnet', 'pro', 'max']).isNotEmpty ? findModel(['sonnet', 'pro', 'max']) : defaultModel;
    final opus = findModel(['opus', 'pro', 'max']).isNotEmpty ? findModel(['opus', 'pro', 'max']) : defaultModel;
    final fable = findModel(['fable', 'sonnet', 'pro']).isNotEmpty ? findModel(['fable', 'sonnet', 'pro']) : defaultModel;
    final haiku = findModel(['haiku', 'flash', 'mini', 'lite']).isNotEmpty ? findModel(['haiku', 'flash', 'mini', 'lite']) : _remoteModels.last;

    setState(() {
      if (sonnet.isNotEmpty) {
        _sonnetDisplayCtrl.text = sonnet;
        _sonnetActualCtrl.text = sonnet;
        _sonnet1M = true;
      }
      if (opus.isNotEmpty) {
        _opusDisplayCtrl.text = opus;
        _opusActualCtrl.text = opus;
        _opus1M = true;
      }
      if (fable.isNotEmpty) {
        _fableDisplayCtrl.text = fable;
        _fableActualCtrl.text = fable;
        _fable1M = true;
      }
      if (haiku.isNotEmpty) {
        _haikuDisplayCtrl.text = haiku;
        _haikuActualCtrl.text = haiku;
        _haiku1M = false;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已根据从后端获取的模型完成一键预设')),
    );
  }

  /// 一键预设点击处理
  Future<void> _handlePreset() async {
    if (_remoteModels.isEmpty) {
      await _fetchModelsFromBackend();
    } else {
      _autoPresetModels();
    }
  }

  /// 动态生成当前的 settings.json 预览
  String _buildPreviewJson() {
    final env = <String, String>{};

    if (_apiBaseUrlCtrl.text.trim().isNotEmpty) {
      env['ANTHROPIC_BASE_URL'] = _apiBaseUrlCtrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    }

    if (_apiKeyCtrl.text.trim().isNotEmpty) {
      env[_authField] = _apiKeyCtrl.text.trim();
    }

    if (_sonnetActualCtrl.text.trim().isNotEmpty) {
      final actual = _sonnetActualCtrl.text.trim();
      final suffix = _sonnet1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = '$actual$suffix';
      env['ANTHROPIC_DEFAULT_SONNET_MODEL_NAME'] =
          _sonnetDisplayCtrl.text.trim().isNotEmpty ? _sonnetDisplayCtrl.text.trim() : actual;
    }

    if (_opusActualCtrl.text.trim().isNotEmpty) {
      final actual = _opusActualCtrl.text.trim();
      final suffix = _opus1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = '$actual$suffix';
      env['ANTHROPIC_DEFAULT_OPUS_MODEL_NAME'] =
          _opusDisplayCtrl.text.trim().isNotEmpty ? _opusDisplayCtrl.text.trim() : actual;
    }

    if (_fableActualCtrl.text.trim().isNotEmpty) {
      final actual = _fableActualCtrl.text.trim();
      final suffix = _fable1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_FABLE_MODEL'] = '$actual$suffix';
      env['ANTHROPIC_DEFAULT_FABLE_MODEL_NAME'] =
          _fableDisplayCtrl.text.trim().isNotEmpty ? _fableDisplayCtrl.text.trim() : actual;
    }

    if (_haikuActualCtrl.text.trim().isNotEmpty) {
      final actual = _haikuActualCtrl.text.trim();
      final suffix = _haiku1M ? '[1M]' : '';
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = '$actual$suffix';
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME'] =
          _haikuDisplayCtrl.text.trim().isNotEmpty ? _haikuDisplayCtrl.text.trim() : actual;
    }

    if (_disableNonEssentialTraffic) {
      env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1';
    }

    if (_disableAutoUpdate) {
      env['DISABLE_AUTO_UPDATE'] = '1';
    }

    if (_maxThinking) {
      env['MAX_THINKING_TOKENS'] = '31999';
    }

    if (_teammatesMode) {
      env['TEAMMATES_MODE'] = '1';
    }

    if (_enableToolSearch) {
      env['ENABLE_TOOL_SEARCH'] = '1';
    }

    final root = <String, dynamic>{
      'env': env,
      'includeCoAuthoredBy': !_hideCoAuthoredBy,
      'enableToolSearch': _enableToolSearch,
      'alwaysThinkingEnabled': _maxThinking,
      'teammates': _teammatesMode,
    };

    return const JsonEncoder.withIndent('  ').convert(root);
  }

  /// 保存配置
  Future<void> _handleSave() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final sonnet = ClaudeModelRoleMapping(
      displayName: _sonnetDisplayCtrl.text.trim(),
      actualModel: _sonnetActualCtrl.text.trim(),
      is1M: _sonnet1M,
    );

    final opus = ClaudeModelRoleMapping(
      displayName: _opusDisplayCtrl.text.trim(),
      actualModel: _opusActualCtrl.text.trim(),
      is1M: _opus1M,
    );

    final fable = ClaudeModelRoleMapping(
      displayName: _fableDisplayCtrl.text.trim(),
      actualModel: _fableActualCtrl.text.trim(),
      is1M: _fable1M,
    );

    final haiku = ClaudeModelRoleMapping(
      displayName: _haikuDisplayCtrl.text.trim(),
      actualModel: _haikuActualCtrl.text.trim(),
      is1M: _haiku1M,
    );

    final apiKey = _apiKeyCtrl.text.trim();

    ClaudeProfile result;
    if (widget.profile == null) {
      result = await _profileService.createProfile(
        name: name,
        remark: _remarkCtrl.text.trim(),
        websiteUrl: _websiteCtrl.text.trim(),
        authType: 'api_key',
        apiKey: apiKey.isNotEmpty ? apiKey : null,
        apiBaseUrl: _apiBaseUrlCtrl.text.trim(),
        apiFormat: _apiFormat,
        authField: _authField,
        sonnetMapping: sonnet,
        opusMapping: opus,
        fableMapping: fable,
        haikuMapping: haiku,
        defaultFallbackModel: _fallbackModelCtrl.text.trim(),
        userAgent: _userAgentCtrl.text.trim(),
        hideCoAuthoredBy: _hideCoAuthoredBy,
        disableNonEssentialTraffic: _disableNonEssentialTraffic,
        disableAutoUpdate: _disableAutoUpdate,
        enableToolSearch: _enableToolSearch,
        maxThinking: _maxThinking,
        teammatesMode: _teammatesMode,
      );
    } else {
      final p = widget.profile!;
      p.name = name;
      p.remark = _remarkCtrl.text.trim();
      p.websiteUrl = _websiteCtrl.text.trim();
      p.authType = 'api_key';
      p.apiBaseUrl = _apiBaseUrlCtrl.text.trim();
      p.apiFormat = _apiFormat;
      p.authField = _authField;
      p.sonnetMapping = sonnet;
      p.opusMapping = opus;
      p.fableMapping = fable;
      p.haikuMapping = haiku;
      p.defaultFallbackModel = _fallbackModelCtrl.text.trim();
      p.userAgent = _userAgentCtrl.text.trim();
      p.hideCoAuthoredBy = _hideCoAuthoredBy;
      p.disableNonEssentialTraffic = _disableNonEssentialTraffic;
      p.disableAutoUpdate = _disableAutoUpdate;
      p.enableToolSearch = _enableToolSearch;
      p.maxThinking = _maxThinking;
      p.teammatesMode = _teammatesMode;

      await _profileService.updateProfile(profile: p, newApiKey: apiKey.isNotEmpty ? apiKey : null);
      result = p;
    }

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AgentHubTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AgentHubTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: AgentHubTheme.cardBackground,
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
          child: Column(
            children: [
              // 顶栏标题 (实体不透明背景)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AgentHubTheme.cardBackground,
                  border: Border(bottom: BorderSide(color: AgentHubTheme.divider)),
                ),
                child: Row(
                  children: [
                    Text(
                      widget.profile == null ? '新建供应商配置' : '编辑供应商配置',
                      style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, size: 18, color: AgentHubTheme.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            // 内容滚动区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 供应商名称与备注
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('供应商名称', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                              const SizedBox(height: 6),
                              _buildTextField(_nameCtrl, '请输入配置名称'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('备注', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                              const SizedBox(height: 6),
                              _buildTextField(_remarkCtrl, '请输入备注说明'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 官网链接
                    Text('官网链接', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildTextField(_websiteCtrl, '请输入官网链接'),
                    const SizedBox(height: 16),
                    // API Key
                    Text('API Key (将安全存储于系统安全凭证库)', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _apiKeyCtrl,
                      obscureText: _obscureApiKey,
                      cursorWidth: 1.5,
                      cursorRadius: const Radius.circular(1),
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, letterSpacing: 0.8),
                      decoration: InputDecoration(
                        hintText: '请输入访问密钥',
                        hintStyle: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13),
                        filled: true,
                        fillColor: AgentHubTheme.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AgentHubTheme.border)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 16, color: AgentHubTheme.textSecondary),
                          onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 请求地址
                    Text('请求地址', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildTextField(_apiBaseUrlCtrl, '请输入服务端点地址，不要以斜杠结尾'),
                    const SizedBox(height: 20),
                    // 高级选项折叠
                    InkWell(
                      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                      child: Row(
                        children: [
                          Icon(_showAdvanced ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 18, color: AgentHubTheme.textPrimary),
                          const SizedBox(width: 4),
                          Text('高级选项', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    if (_showAdvanced) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('API 格式', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                                const SizedBox(height: 6),
                                _buildDropdown(['Anthropic Messages(原生)'], _apiFormat, (v) => setState(() => _apiFormat = v!)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('认证字段', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                                const SizedBox(height: 6),
                                _buildDropdown(['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'], _authField, (v) => setState(() => _authField = v!)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 模型映射表格
                      Row(
                        children: [
                          Text('模型映射', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '显示名称只影响 /model 菜单，1M 声明上下文能力',
                              style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isFetchingModels ? null : _handlePreset,
                            icon: const Icon(Icons.tune, size: 14),
                            label: const Text('一键预设', style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AgentHubTheme.textPrimary,
                              side: BorderSide(color: AgentHubTheme.border),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isFetchingModels ? null : _fetchModelsFromBackend,
                            icon: _isFetchingModels
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.cloud_download_outlined, size: 14),
                            label: Text(_isFetchingModels ? '获取中...' : '获取模型列表', style: const TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AgentHubTheme.textPrimary,
                              side: BorderSide(color: AgentHubTheme.border),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildModelMappingRow('Sonnet', _sonnetDisplayCtrl, _sonnetActualCtrl, _sonnet1M, (v) => setState(() => _sonnet1M = v!)),
                      _buildModelMappingRow('Opus', _opusDisplayCtrl, _opusActualCtrl, _opus1M, (v) => setState(() => _opus1M = v!)),
                      _buildModelMappingRow('Fable', _fableDisplayCtrl, _fableActualCtrl, _fable1M, (v) => setState(() => _fable1M = v!)),
                      _buildModelMappingRow('Haiku', _haikuDisplayCtrl, _haikuActualCtrl, _haiku1M, (v) => setState(() => _haiku1M = v!)),
                      const SizedBox(height: 12),
                      Text('默认兜底模型', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                      const SizedBox(height: 6),
                      _buildTextField(_fallbackModelCtrl, '请输入兜底请求模型'),
                      const SizedBox(height: 12),
                      Text('自定义 User-Agent', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                      const SizedBox(height: 6),
                      _buildTextField(_userAgentCtrl, '请输入 User-Agent'),
                    ],
                    const SizedBox(height: 20),
                    Divider(height: 1, color: AgentHubTheme.divider),
                    const SizedBox(height: 16),
                    // 快捷开关
                    Text('配置特性开关', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildCheckbox('隐藏 AI 署名', _hideCoAuthoredBy, (v) => setState(() => _hideCoAuthoredBy = v!)),
                        _buildCheckbox('Teammates 模式', _teammatesMode, (v) => setState(() => _teammatesMode = v!)),
                        _buildCheckbox('启用 Tool Search', _enableToolSearch, (v) => setState(() => _enableToolSearch = v!)),
                        _buildCheckbox('最大强度思考', _maxThinking, (v) => setState(() => _maxThinking = v!)),
                        _buildCheckbox('禁用自动升级', _disableAutoUpdate, (v) => setState(() => _disableAutoUpdate = v!)),
                        _buildCheckbox('禁用非必要流量', _disableNonEssentialTraffic, (v) => setState(() => _disableNonEssentialTraffic = v!)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 实时生成的 JSON 配置预览
                    Text('生成的 settings.json 配置预览', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AgentHubTheme.isDark ? const Color(0xFF141414) : const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        _buildPreviewJson(),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFE0E0E0), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部操作按钮 (实体不透明背景)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AgentHubTheme.cardBackground,
                border: Border(top: BorderSide(color: AgentHubTheme.divider)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('取消', style: TextStyle(color: AgentHubTheme.textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgentHubTheme.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('保存配置'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildTextField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(1),
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, letterSpacing: 0.8),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13, letterSpacing: 0.8),
        filled: true,
        fillColor: AgentHubTheme.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AgentHubTheme.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AgentHubTheme.border)),
      ),
    );
  }

  Widget _buildDropdown(List<String> items, String current, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AgentHubTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgentHubTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(current) ? current : items.first,
          isExpanded: true,
          dropdownColor: AgentHubTheme.cardBackground,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(fontSize: 13, color: AgentHubTheme.textPrimary)))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildModelMappingRow(
    String role,
    TextEditingController displayCtrl,
    TextEditingController actualCtrl,
    bool is1M,
    ValueChanged<bool?> on1MChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(role, style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: _buildTextField(displayCtrl, '请输入显示名称'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildTextField(actualCtrl, '请输入实际请求模型')),
                if (_remoteModels.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: '选择从后端拉取的模型',
                    icon: Icon(Icons.arrow_drop_down, color: AgentHubTheme.textSecondary, size: 20),
                    padding: EdgeInsets.zero,
                    onSelected: (model) {
                      actualCtrl.text = model;
                      if (displayCtrl.text.isEmpty) {
                        displayCtrl.text = model;
                      }
                      setState(() {});
                    },
                    itemBuilder: (context) {
                      return _remoteModels.map((m) {
                        return PopupMenuItem(
                          value: m,
                          height: 32,
                          child: Text(m, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: is1M,
                activeColor: AgentHubTheme.primaryRed,
                onChanged: on1MChanged,
              ),
              const Text('声明 1M', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          activeColor: AgentHubTheme.primaryRed,
          onChanged: onChanged,
        ),
        Text(label, style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 12)),
      ],
    );
  }
}

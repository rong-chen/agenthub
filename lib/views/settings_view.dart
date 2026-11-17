import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gateway_config.dart';
import '../providers/app_state_provider.dart';
import '../theme/openclaw_theme.dart';

/// OpenClaw 风格系统与网关设置视图
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _gatewayPortController;
  late TextEditingController _apiBaseUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelNameController;
  late TextEditingController _customSkillsPathController;
  late bool _autoStartGateway;
  late bool _minimizeToTray;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppStateProvider>().config;
    _gatewayPortController = TextEditingController(text: config.gatewayPort.toString());
    _apiBaseUrlController = TextEditingController(text: config.apiBaseUrl);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _modelNameController = TextEditingController(text: config.modelName);
    _customSkillsPathController = TextEditingController(text: config.customSkillsPath);
    _autoStartGateway = config.autoStartGateway;
    _minimizeToTray = config.minimizeToTrayOnClose;
  }

  @override
  void dispose() {
    _gatewayPortController.dispose();
    _apiBaseUrlController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    _customSkillsPathController.dispose();
    super.dispose();
  }

  /// 切换网关启动与停止
  Future<void> _handleToggleGateway() async {
    final provider = context.read<AppStateProvider>();
    if (provider.isGatewayRunning) {
      await provider.stopLocalGateway();
    } else {
      await provider.startLocalGateway();
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(provider.gatewayStatusMessage),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 保存设置
  Future<void> _handleSave() async {
    final provider = context.read<AppStateProvider>();
    final port = int.tryParse(_gatewayPortController.text.trim()) ?? 18789;

    final newConfig = GatewayConfig(
      gatewayPort: port,
      autoStartGateway: _autoStartGateway,
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
      customSkillsPath: _customSkillsPathController.text.trim(),
      minimizeToTrayOnClose: _minimizeToTray,
    );

    await provider.updateConfig(newConfig);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('配置已保存'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();

    return Container(
      color: OpenClawTheme.background,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        children: [
          _buildHeaderRow(),
          const SizedBox(height: 8),
          const Text(
            '本地网关服务与大模型上游接入配置',
            style: TextStyle(fontSize: 13, color: OpenClawTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          _buildLocalGatewaySection(provider),
          const SizedBox(height: 16),
          _buildUpstreamModelSection(),
          const SizedBox(height: 16),
          _buildCommonSection(),
          const SizedBox(height: 24),
          _buildActionButtons(),
        ],
      ),
    );
  }

  /// 页面标题
  Widget _buildHeaderRow() {
    return const Text(
      '系统设置',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: OpenClawTheme.titleRed,
      ),
    );
  }

  /// 本地网关服务配置卡片
  Widget _buildLocalGatewaySection(AppStateProvider provider) {
    final isOnline = provider.isGatewayOnline;
    final statusColor = isOnline ? OpenClawTheme.statusGreen : OpenClawTheme.statusGray;
    final statusText = isOnline
        ? '网关在线: http://127.0.0.1:${provider.gatewayPort}'
        : provider.gatewayStatusMessage;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OpenClawTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '本地网关服务',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: OpenClawTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: '本地监听端口',
            controller: _gatewayPortController,
            hint: '18789',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '启动应用时自动开启本地网关',
              style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
            ),
            value: _autoStartGateway,
            activeThumbColor: OpenClawTheme.primaryRed,
            onChanged: (val) {
              setState(() => _autoStartGateway = val);
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _handleToggleGateway,
            style: OutlinedButton.styleFrom(
              foregroundColor: isOnline ? OpenClawTheme.primaryRed : OpenClawTheme.textPrimary,
              side: BorderSide(
                color: isOnline ? OpenClawTheme.primaryRed : OpenClawTheme.border,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(isOnline ? '停止网关' : '立即启动网关'),
          ),
        ],
      ),
    );
  }

  /// 上游大模型服务配置卡片
  Widget _buildUpstreamModelSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OpenClawTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '上游大语言模型接入',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: OpenClawTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'API Base URL',
            controller: _apiBaseUrlController,
            hint: 'https://api.openai.com/v1',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            label: 'API Key',
            controller: _apiKeyController,
            hint: 'sk-...',
            isPassword: true,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            label: '模型名称',
            controller: _modelNameController,
            hint: 'gpt-4o-mini',
          ),
        ],
      ),
    );
  }

  /// 系统与托盘常驻配置卡片
  Widget _buildCommonSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OpenClawTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '系统与常驻运行配置',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: OpenClawTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: '附加插件扫描目录 (可选绝对路径)',
            controller: _customSkillsPathController,
            hint: '默认扫描 ~/.agenthub/skills 与工程 skills/ 目录',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '关闭主窗口时最小化到系统托盘 (保持后台常驻运行)',
              style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary),
            ),
            value: _minimizeToTray,
            activeColor: OpenClawTheme.primaryRed,
            onChanged: (val) {
              if (val != null) {
                setState(() => _minimizeToTray = val);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 输入框封装
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: OpenClawTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: OpenClawTheme.border),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: const TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: OpenClawTheme.textTertiary, fontSize: 13),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  /// 底部保存按钮
  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton(
          onPressed: _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: OpenClawTheme.primaryRed,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('保存配置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

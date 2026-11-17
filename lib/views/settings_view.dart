import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gateway_config.dart';
import '../providers/app_state_provider.dart';
import '../theme/openclaw_theme.dart';

/// 系统设置视图（含主题切换）
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
  late String _themeMode;

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
    _themeMode = config.themeMode;
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

  Future<void> _handleToggleGateway() async {
    final provider = context.read<AppStateProvider>();
    if (provider.isGatewayRunning) {
      await provider.stopLocalGateway();
    } else {
      await provider.startLocalGateway();
    }
  }

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
      themeMode: _themeMode,
    );
    await provider.updateConfig(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();

    return Container(
      color: OpenClawTheme.background,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        children: [
          Text('系统设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: OpenClawTheme.titleRed)),
          const SizedBox(height: 20),
          // 主题设置
          _buildCard([
            Text('主题', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: OpenClawTheme.textPrimary)),
            const SizedBox(height: 14),
            Row(
              children: [
                _themeOption('明亮', 'light'),
                const SizedBox(width: 12),
                _themeOption('暗黑', 'dark'),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          // 网关配置
          _buildCard([
            Row(children: [
              Text('网关', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: OpenClawTheme.textPrimary)),
              const Spacer(),
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(color: provider.isGatewayOnline ? OpenClawTheme.statusGreen : OpenClawTheme.statusGray, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                provider.isGatewayOnline ? '在线' : '离线',
                style: TextStyle(fontSize: 12, color: provider.isGatewayOnline ? OpenClawTheme.statusGreen : OpenClawTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 14),
            _buildField('端口', _gatewayPortController, ''),
            const SizedBox(height: 12),
            Row(children: [
              Text('自动启动', style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary)),
              const Spacer(),
              Switch(value: _autoStartGateway, activeColor: OpenClawTheme.primaryRed, onChanged: (val) => setState(() => _autoStartGateway = val)),
            ]),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _handleToggleGateway,
              style: OutlinedButton.styleFrom(
                foregroundColor: provider.isGatewayOnline ? OpenClawTheme.primaryRed : OpenClawTheme.textPrimary,
                side: BorderSide(color: provider.isGatewayOnline ? OpenClawTheme.primaryRed : OpenClawTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(provider.isGatewayOnline ? '停止' : '启动'),
            ),
          ]),
          const SizedBox(height: 16),
          // 大模型配置
          _buildCard([
            Text('模型服务', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: OpenClawTheme.textPrimary)),
            const SizedBox(height: 14),
            _buildField('服务地址', _apiBaseUrlController, ''),
            const SizedBox(height: 12),
            _buildField('访问密钥', _apiKeyController, '', isPassword: true),
            const SizedBox(height: 12),
            _buildField('模型', _modelNameController, ''),
          ]),
          const SizedBox(height: 16),
          // 通用配置
          _buildCard([
            Text('常规', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: OpenClawTheme.textPrimary)),
            const SizedBox(height: 14),
            _buildField('插件目录', _customSkillsPathController, ''),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('最小化到托盘', style: TextStyle(fontSize: 13, color: OpenClawTheme.textPrimary))),
              Switch(value: _minimizeToTray, activeColor: OpenClawTheme.primaryRed, onChanged: (val) => setState(() => _minimizeToTray = val)),
            ]),
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ElevatedButton(
              onPressed: _handleSave,
              style: ElevatedButton.styleFrom(backgroundColor: OpenClawTheme.primaryRed, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('保存', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _themeOption(String label, String value) {
    final sel = _themeMode == value;
    return InkWell(
      onTap: () {
        setState(() => _themeMode = value);
        final provider = context.read<AppStateProvider>();
        if (provider.config.themeMode != value) {
          final newConfig = provider.config;
          newConfig.themeMode = value;
          provider.updateConfig(newConfig);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: sel ? OpenClawTheme.primaryRedLight : OpenClawTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? OpenClawTheme.primaryRed : OpenClawTheme.border, width: sel ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(value == 'light' ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: sel ? OpenClawTheme.primaryRed : OpenClawTheme.textSecondary),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? OpenClawTheme.primaryRed : OpenClawTheme.textPrimary)),
        ]),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: OpenClawTheme.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: OpenClawTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {bool isPassword = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: OpenClawTheme.textSecondary)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        obscureText: isPassword,
        style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: OpenClawTheme.textTertiary, fontSize: 13),
          filled: true,
          fillColor: OpenClawTheme.inputBackground,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: OpenClawTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: OpenClawTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: OpenClawTheme.primaryRed),
          ),
        ),
      ),
    ]);
  }
}

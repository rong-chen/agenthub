import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/gateway_config.dart';
import '../providers/app_state_provider.dart';
import '../services/wechat_channel_service.dart';
import '../theme/agenthub_theme.dart';

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
  late TextEditingController _httpProxyController;
  late TextEditingController _temperatureController;
  late TextEditingController _topPController;
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
    _httpProxyController = TextEditingController(text: config.httpProxy);
    _temperatureController = TextEditingController(text: config.temperature.toString());
    _topPController = TextEditingController(text: config.topP.toString());
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
    _httpProxyController.dispose();
    _temperatureController.dispose();
    _topPController.dispose();
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
    final temp = double.tryParse(_temperatureController.text.trim()) ?? 0.7;
    final topP = double.tryParse(_topPController.text.trim()) ?? 0.9;

    final newConfig = GatewayConfig(
      gatewayPort: port,
      autoStartGateway: _autoStartGateway,
      apiBaseUrl: _apiBaseUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
      customSkillsPath: _customSkillsPathController.text.trim(),
      minimizeToTrayOnClose: _minimizeToTray,
      themeMode: provider.config.themeMode,
      httpProxy: _httpProxyController.text.trim(),
      temperature: temp,
      topP: topP,
      wechatChannelEnabled: provider.config.wechatChannelEnabled,
      wechatAutoReply: provider.config.wechatAutoReply,
    );
    await provider.updateConfig(newConfig);
  }

  void _showWechatQrDialog(BuildContext context, AppStateProvider provider) {
    if (!provider.wechatService.isRunning && provider.config.wechatChannelEnabled) {
      provider.refreshWechatQrCode();
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<AppStateProvider>(
          builder: (context, p, child) {
            final wechat = p.wechatService;
            final isRunning = wechat.isRunning;
            final isWaitingScan = wechat.status == WechatChannelStatus.waitingScan;
            final isGettingQr = wechat.status == WechatChannelStatus.gettingQr;

            return AlertDialog(
              backgroundColor: AgentHubTheme.cardBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AgentHubTheme.border)),
              title: Row(
                children: [
                  Icon(Icons.forum_outlined, size: 20, color: const Color(0xFF07C160)),
                  const SizedBox(width: 8),
                  Text('微信通道状态', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isGettingQr) ...[
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(height: 12),
                      Text('正在获取登录二维码...', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                    ] else if (isWaitingScan && wechat.qrCodeText != null && wechat.qrCodeText!.isNotEmpty) ...[
                      Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        alignment: Alignment.center,
                        child: QrImageView(
                          data: wechat.qrCodeText!,
                          version: QrVersions.auto,
                          size: 160.0,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('请使用微信扫描上方二维码登录', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('有效时间还剩 ${wechat.qrCodeRemainingSeconds} 秒', style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 11)),
                    ] else if (isRunning) ...[
                      Icon(Icons.check_circle_outline, size: 36, color: AgentHubTheme.statusGreen),
                      const SizedBox(height: 8),
                      Text('已成功连接微信', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('当前登录: ${wechat.accountName ?? "微信用户"}', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12)),
                    ] else ...[
                      Icon(Icons.qr_code_2_outlined, size: 40, color: AgentHubTheme.textTertiary),
                      const SizedBox(height: 8),
                      Text(
                        p.config.wechatChannelEnabled
                            ? (wechat.lastError ?? '请点击下方按钮获取扫码二维码')
                            : '微信通道尚未启用，请先开启微信通道开关',
                        style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (p.config.wechatChannelEnabled && !isRunning)
                  OutlinedButton(
                    onPressed: () async {
                      await p.refreshWechatQrCode();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AgentHubTheme.textPrimary,
                      side: BorderSide(color: AgentHubTheme.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('重新获取二维码'),
                  ),
                if (isRunning)
                  OutlinedButton(
                    onPressed: () async {
                      await p.stopWechatChannel();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AgentHubTheme.primaryRed,
                      side: const BorderSide(color: AgentHubTheme.primaryRed),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('断开连接'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('关闭', style: TextStyle(color: AgentHubTheme.textSecondary)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showResetConfirmDialog(BuildContext context, AppStateProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AgentHubTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AgentHubTheme.border)),
          title: Text('确认清空会话数据', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Text('此操作将清空本地数据库中的所有会话与消息历史记录。', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: AgentHubTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await provider.resetAllSessions();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AgentHubTheme.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('确认清空'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    AgentHubTheme.isDark = provider.isDarkTheme;

    return Container(
      color: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        children: [
          Text('系统设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AgentHubTheme.titleRed)),
          const SizedBox(height: 20),
          // 主题设置
          _buildCard([
            Text('主题', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary)),
            const SizedBox(height: 14),
            Row(
              children: [
                _themeOption('明亮', 'light', provider.config.themeMode),
                const SizedBox(width: 12),
                _themeOption('暗黑', 'dark', provider.config.themeMode),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          // 网关配置
          _buildCard([
            Row(children: [
              Text('网关', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary)),
              const Spacer(),
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(color: provider.isGatewayOnline ? AgentHubTheme.statusGreen : AgentHubTheme.statusGray, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                provider.isGatewayOnline ? '在线' : '离线',
                style: TextStyle(fontSize: 12, color: provider.isGatewayOnline ? AgentHubTheme.statusGreen : AgentHubTheme.textTertiary),
              ),
            ]),
            const SizedBox(height: 14),
            _buildField('端口', _gatewayPortController, ''),
            const SizedBox(height: 12),
            Row(children: [
              Text('自动启动', style: TextStyle(fontSize: 13, color: AgentHubTheme.textPrimary)),
              const Spacer(),
              Switch(value: _autoStartGateway, activeThumbColor: AgentHubTheme.primaryRed, onChanged: (val) => setState(() => _autoStartGateway = val)),
            ]),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _handleToggleGateway,
              style: OutlinedButton.styleFrom(
                foregroundColor: provider.isGatewayOnline ? AgentHubTheme.primaryRed : AgentHubTheme.textPrimary,
                side: BorderSide(color: provider.isGatewayOnline ? AgentHubTheme.primaryRed : AgentHubTheme.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(provider.isGatewayOnline ? '停止' : '启动'),
            ),
          ]),
          const SizedBox(height: 16),
          // 大模型配置
          _buildCard([
            Text('模型服务', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary)),
            const SizedBox(height: 14),
            _buildField('服务地址', _apiBaseUrlController, ''),
            const SizedBox(height: 12),
            _buildField('访问密钥', _apiKeyController, '', isPassword: true),
            const SizedBox(height: 12),
            _buildField('模型', _modelNameController, ''),
            const SizedBox(height: 12),
            _buildField('网络代理', _httpProxyController, ''),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildField('温度 (0.0-2.0)', _temperatureController, '0.7')),
                const SizedBox(width: 12),
                Expanded(child: _buildField('Top_P (0.0-1.0)', _topPController, '0.9')),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          // 通用配置
          _buildCard([
            Text('常规', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary)),
            const SizedBox(height: 14),
            _buildField('插件目录', _customSkillsPathController, ''),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('最小化到托盘', style: TextStyle(fontSize: 13, color: AgentHubTheme.textPrimary))),
              Switch(value: _minimizeToTray, activeThumbColor: AgentHubTheme.primaryRed, onChanged: (val) => setState(() => _minimizeToTray = val)),
            ]),
            const SizedBox(height: 14),
            Divider(height: 1, color: AgentHubTheme.divider),
            const SizedBox(height: 14),
            Row(children: [
              Text('会话数据管理', style: TextStyle(fontSize: 13, color: AgentHubTheme.textPrimary)),
              const Spacer(),
              OutlinedButton(
                onPressed: () => _showResetConfirmDialog(context, provider),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AgentHubTheme.primaryRed,
                  side: const BorderSide(color: AgentHubTheme.primaryRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('清空历史数据', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          // 微信通道配置
          _buildCard([
            Row(children: [
              Icon(Icons.forum_outlined, size: 18, color: const Color(0xFF07C160)),
              const SizedBox(width: 8),
              Text('微信通道', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary)),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: provider.wechatService.isRunning ? AgentHubTheme.statusGreen : AgentHubTheme.statusGray,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                provider.wechatService.isRunning ? '已连接' : '未连接',
                style: TextStyle(
                  fontSize: 12,
                  color: provider.wechatService.isRunning ? AgentHubTheme.statusGreen : AgentHubTheme.textTertiary,
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('启用微信通道', style: TextStyle(fontSize: 13, color: AgentHubTheme.textPrimary))),
              Switch(
                value: provider.config.wechatChannelEnabled,
                activeThumbColor: const Color(0xFF07C160),
                onChanged: (val) async {
                  await provider.toggleWechatChannel(val);
                },
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Text('微信消息自动回复', style: TextStyle(fontSize: 13, color: AgentHubTheme.textPrimary))),
              Switch(
                value: provider.config.wechatAutoReply,
                activeThumbColor: const Color(0xFF07C160),
                onChanged: (val) async {
                  await provider.setWechatAutoReply(val);
                },
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              OutlinedButton(
                onPressed: () => _showWechatQrDialog(context, provider),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AgentHubTheme.textPrimary,
                  side: BorderSide(color: AgentHubTheme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: Text(
                  provider.wechatService.isRunning ? '查看通道状态' : '扫码接入微信',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ElevatedButton(
              onPressed: _handleSave,
              style: ElevatedButton.styleFrom(backgroundColor: AgentHubTheme.primaryRed, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('保存', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _themeOption(String label, String value, String currentMode) {
    final sel = currentMode == value;
    return InkWell(
      onTap: () {
        final provider = context.read<AppStateProvider>();
        if (provider.config.themeMode != value) {
          final newConfig = provider.config.copyWith(themeMode: value);
          provider.updateConfig(newConfig);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: sel ? AgentHubTheme.primaryRedLight : AgentHubTheme.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? AgentHubTheme.primaryRed : AgentHubTheme.border, width: sel ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(value == 'light' ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: sel ? AgentHubTheme.primaryRed : AgentHubTheme.textSecondary),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.bold : FontWeight.normal, color: sel ? AgentHubTheme.primaryRed : AgentHubTheme.textPrimary)),
        ]),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AgentHubTheme.cardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: AgentHubTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {bool isPassword = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        obscureText: isPassword,
        style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13),
          filled: true,
          fillColor: AgentHubTheme.inputBackground,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AgentHubTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AgentHubTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AgentHubTheme.primaryRed),
          ),
        ),
      ),
    ]);
  }
}

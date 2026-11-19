import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'claude_profile_edit_dialog.dart';
import '../models/claude_env_info.dart';
import '../models/claude_profile.dart';
import '../providers/app_state_provider.dart';
import '../services/claude_env_service.dart';
import '../services/claude_profile_service.dart';
import '../theme/agenthub_theme.dart';

/// Claude Code 账号配置与会话用量管理视图
class ClaudeManagerView extends StatefulWidget {
  const ClaudeManagerView({super.key});

  @override
  State<ClaudeManagerView> createState() => _ClaudeManagerViewState();
}

class _ClaudeManagerViewState extends State<ClaudeManagerView> {
  final ClaudeEnvService _envService = ClaudeEnvService.instance;
  final ClaudeProfileService _profileService = ClaudeProfileService.instance;

  ClaudeEnvInfo? _envInfo;
  bool _isCheckingEnv = true;

  List<ClaudeProfile> _profiles = [];
  ClaudeProfile? _selectedProfile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载环境检测结果与 Profiles
  Future<void> _loadData() async {
    setState(() => _isCheckingEnv = true);

    final env = await _envService.detectEnvironment();
    final profiles = await _profileService.loadProfiles();

    if (mounted) {
      setState(() {
        _envInfo = env;
        _profiles = profiles;
        if (_selectedProfile == null && profiles.isNotEmpty) {
          _selectedProfile = profiles.first;
        }
        _isCheckingEnv = false;
      });
    }
  }

  /// 刷新环境信息
  Future<void> _refreshEnv() async {
    setState(() => _isCheckingEnv = true);
    final env = await _envService.detectEnvironment();
    if (mounted) {
      setState(() {
        _envInfo = env;
        _isCheckingEnv = false;
      });
    }
  }

  /// 弹出新建或编辑 Profile 抽屉弹窗
  Future<void> _showCreateProfileDialog([ClaudeProfile? existing]) async {
    final result = await ClaudeProfileEditDialog.show(context, profile: existing);
    if (result != null) {
      await _loadData();
      setState(() {
        _selectedProfile = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentHubTheme.background,
      body: Column(
        children: [
          // 顶部环境检测条
          _buildEnvironmentStatusBar(),
          Divider(height: 1, color: AgentHubTheme.divider),
          // 主工作区：左侧 Profile 管理 + 右侧配置会话与用量面板
          Expanded(
            child: Row(
              children: [
                _buildProfileSidebar(),
                VerticalDivider(width: 1, color: AgentHubTheme.divider),
                Expanded(child: _buildProfileDetailArea()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部环境检测状态栏
  Widget _buildEnvironmentStatusBar() {
    final env = _envInfo;
    final isInstalled = env?.isInstalled == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AgentHubTheme.cardBackground,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isInstalled ? AgentHubTheme.statusGreen : AgentHubTheme.primaryRed,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isInstalled ? 'Claude Code 引擎已就绪' : 'Claude Code 未检测到安装',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AgentHubTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          if (isInstalled) ...[
            Text('版本: ${env?.version ?? "未知"}', style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '路径: ${env?.executablePath ?? ""}',
                style: TextStyle(fontSize: 11, color: AgentHubTheme.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                '安装引导: 请在终端执行 npm install -g @anthropic-ai/claude-code',
                style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: 'npm install -g @anthropic-ai/claude-code'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制安装命令到剪贴板')),
                );
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                side: BorderSide(color: AgentHubTheme.border),
              ),
              child: const Text('复制安装命令', style: TextStyle(fontSize: 11)),
            ),
          ],
          IconButton(
            icon: _isCheckingEnv
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.refresh, size: 16, color: AgentHubTheme.textSecondary),
            tooltip: '重新检测环境',
            onPressed: _isCheckingEnv ? null : _refreshEnv,
          ),
        ],
      ),
    );
  }

  /// 左侧 Profile 列表侧边栏
  Widget _buildProfileSidebar() {
    return Container(
      width: 220,
      color: AgentHubTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Text('账号配置', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AgentHubTheme.textSecondary)),
                const Spacer(),
                InkWell(
                  onTap: _showCreateProfileDialog,
                  child: Icon(Icons.add, size: 16, color: AgentHubTheme.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AgentHubTheme.divider),
          Expanded(
            child: _profiles.isEmpty
                ? Center(
                    child: Text('暂无配置\n点击右上角新建', style: TextStyle(fontSize: 12, color: AgentHubTheme.textTertiary), textAlign: TextAlign.center),
                  )
                : ListView.builder(
                    itemCount: _profiles.length,
                    itemBuilder: (context, idx) {
                      final p = _profiles[idx];
                      final isSelected = p.id == _selectedProfile?.id;

                      return InkWell(
                        onTap: () => setState(() => _selectedProfile = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          color: isSelected ? AgentHubTheme.primaryRedLight : Colors.transparent,
                          child: Row(
                            children: [
                              Icon(
                                p.authType == 'api_key' ? Icons.vpn_key_outlined : Icons.account_circle_outlined,
                                size: 16,
                                color: isSelected ? AgentHubTheme.primaryRed : AgentHubTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? AgentHubTheme.primaryRed : AgentHubTheme.textPrimary,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected) ...[
                                InkWell(
                                  onTap: () => _showCreateProfileDialog(p),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(Icons.edit_outlined, size: 14, color: AgentHubTheme.textTertiary),
                                  ),
                                ),
                                InkWell(
                                  onTap: () async {
                                    await _profileService.deleteProfile(p.id);
                                    await _loadData();
                                  },
                                  child: Icon(Icons.delete_outline, size: 14, color: AgentHubTheme.textTertiary),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 右侧配置详情、会话审计与用量大小面板
  Widget _buildProfileDetailArea() {
    final profile = _selectedProfile;
    if (profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_outlined, size: 40, color: AgentHubTheme.textTertiary),
            const SizedBox(height: 12),
            Text('请在左侧选择或新建配置', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    final provider = context.watch<AppStateProvider>();
    final allSessions = provider.sessions;
    final isFirstProfile = _profiles.isNotEmpty && _profiles.first.id == profile.id;
    final sessions = allSessions.where((s) {
      if (s.profileId != null) {
        return s.profileId == profile.id;
      }
      return isFirstProfile;
    }).toList();

    int totalTokens = 0;
    int totalBytes = 0;
    for (final s in sessions) {
      totalTokens += s.totalTokens;
      totalBytes += s.sizeInBytes;
    }

    final formattedTotalSize = totalBytes < 1024
        ? '$totalBytes B'
        : (totalBytes < 1024 * 1024
            ? '${(totalBytes / 1024).toStringAsFixed(1)} KB'
            : '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB');

    final primaryModel = profile.sonnetMapping.actualModel.isNotEmpty
        ? profile.sonnetMapping.actualModel
        : (profile.defaultFallbackModel.isNotEmpty ? profile.defaultFallbackModel : '默认');

    return Container(
      color: AgentHubTheme.cardBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部配置概要
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AgentHubTheme.cardBackground,
              border: Border(bottom: BorderSide(color: AgentHubTheme.divider)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AgentHubTheme.primaryRedLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    profile.authType == 'api_key' ? Icons.vpn_key_outlined : Icons.account_circle_outlined,
                    size: 20,
                    color: AgentHubTheme.primaryRed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profile.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AgentHubTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AgentHubTheme.background,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AgentHubTheme.border),
                            ),
                            child: Text(
                              profile.authType == 'api_key' ? 'API Key 认证' : 'OAuth 认证',
                              style: TextStyle(fontSize: 11, color: AgentHubTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '请求地址: ${profile.apiBaseUrl.isNotEmpty ? profile.apiBaseUrl : "官方端点"} · 认证字段: ${profile.authField}',
                        style: TextStyle(fontSize: 12, color: AgentHubTheme.textTertiary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showCreateProfileDialog(profile),
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('编辑配置', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgentHubTheme.textPrimary,
                    side: BorderSide(color: AgentHubTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await provider.createNewSession(
                      profileId: profile.id,
                      title: '${profile.name} 会话',
                    );
                  },
                  icon: const Icon(Icons.add_comment_outlined, size: 14),
                  label: const Text('新建会话', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AgentHubTheme.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          // 概览指标卡片
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildMetricCard('关联会话数', '${sessions.length} 个', Icons.chat_bubble_outline),
                const SizedBox(width: 14),
                _buildMetricCard('累计用量', '$totalTokens Tokens', Icons.data_usage_outlined),
                const SizedBox(width: 14),
                _buildMetricCard('会话总大小', formattedTotalSize, Icons.storage_outlined),
                const SizedBox(width: 14),
                _buildMetricCard('主力映射模型', primaryModel, Icons.memory_outlined),
              ],
            ),
          ),
          Divider(height: 1, color: AgentHubTheme.divider),
          // 会话列表标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Text(
                  '使用此配置的会话记录',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary),
                ),
                const SizedBox(width: 8),
                Text(
                  '点击进入对话直接调试与改代码',
                  style: TextStyle(fontSize: 11, color: AgentHubTheme.textTertiary),
                ),
              ],
            ),
          ),
          // 会话列表内容
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 38, color: AgentHubTheme.textTertiary),
                        const SizedBox(height: 10),
                        Text('暂无使用此配置的会话', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('调用修改代码与对话交互在【对话】页面中进行', style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 12)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () async {
                            await provider.createNewSession(profileId: profile.id, title: '${profile.name} 会话');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AgentHubTheme.primaryRed,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('使用此配置开启对话'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final s = sessions[idx];
                      final updateTimeStr = '${s.updatedAt.month}月${s.updatedAt.day}日 ${s.updatedAt.hour}:${s.updatedAt.minute.toString().padLeft(2, '0')}';

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AgentHubTheme.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AgentHubTheme.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.forum_outlined, size: 18, color: AgentHubTheme.primaryRed),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.title,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AgentHubTheme.textPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${s.messages.length} 条消息 · 更新于 $updateTimeStr',
                                    style: TextStyle(fontSize: 11, color: AgentHubTheme.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                            // 用量与大小
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '用量: ${s.totalTokens} Tokens',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AgentHubTheme.textPrimary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '大小: ${s.formattedSize}',
                                  style: TextStyle(fontSize: 11, color: AgentHubTheme.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            // 操作按钮
                            OutlinedButton.icon(
                              onPressed: () {
                                provider.switchSession(s.id);
                                provider.selectTab(0);
                              },
                              icon: const Icon(Icons.login, size: 13),
                              label: const Text('进入对话', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AgentHubTheme.textPrimary,
                                side: BorderSide(color: AgentHubTheme.border),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 16, color: AgentHubTheme.textTertiary),
                              tooltip: '移至回收站',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                await provider.deleteSession(s.id);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 概览指标统计小卡片
  Widget _buildMetricCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AgentHubTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AgentHubTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AgentHubTheme.textSecondary),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 11, color: AgentHubTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

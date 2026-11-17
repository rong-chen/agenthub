import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/app_state_provider.dart';
import '../theme/agenthub_theme.dart';
import 'chat_view.dart';
import 'tasks_view.dart';
import 'skills_view.dart';
import 'settings_view.dart';

/// 主窗口布局，包含左侧边栏与主工作区
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with WindowListener {
  bool _isSidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final provider = context.read<AppStateProvider>();
    if (provider.config.minimizeToTrayOnClose) {
      await windowManager.hide();
      return;
    }
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    // 强制同步当前主题模式，防止静态变量未即时更新
    AgentHubTheme.isDark = provider.isDarkTheme;

    return Scaffold(
      backgroundColor: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      body: Row(
        children: [
          if (!_isSidebarCollapsed) ...[
            _buildSidebar(context, provider),
            VerticalDivider(width: 1, thickness: 1, color: AgentHubTheme.divider),
          ],
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, provider),
                Divider(height: 1, thickness: 1, color: AgentHubTheme.divider),
                Expanded(
                  child: IndexedStack(
                    index: provider.currentTabIndex,
                    children: const [
                      ChatView(),
                      TasksView(),
                      SkillsView(),
                      SettingsView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 会话搜索弹窗
  void _showSearchDialog(BuildContext context, AppStateProvider provider) {
    final searchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final matches = provider.sessions.where((s) {
              if (query.isEmpty) return true;
              if (s.title.toLowerCase().contains(query)) return true;
              return s.messages.any((m) => m.content.toLowerCase().contains(query));
            }).toList();

            return AlertDialog(
              backgroundColor: AgentHubTheme.cardBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AgentHubTheme.border)),
              title: Text('搜索', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setDialogState(() {}),
                      style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AgentHubTheme.background,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AgentHubTheme.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AgentHubTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AgentHubTheme.primaryRed)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: matches.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text('无匹配内容', style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: matches.length,
                              itemBuilder: (ctx, idx) {
                                final s = matches[idx];
                                return ListTile(
                                  dense: true,
                                  title: Text(s.title, style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Icon(Icons.arrow_forward_ios, size: 12, color: AgentHubTheme.textTertiary),
                                  onTap: () {
                                    provider.switchSession(s.id);
                                    provider.selectTab(0);
                                    Navigator.of(ctx).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
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

  /// 顶栏工具行
  Widget _buildTopBar(BuildContext context, AppStateProvider provider) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      child: Row(
        children: [
          InkWell(
            onTap: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AgentHubTheme.cardBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgentHubTheme.border),
              ),
              child: Icon(Icons.view_sidebar_outlined, size: 16, color: AgentHubTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _showSearchDialog(context, provider),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AgentHubTheme.cardBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgentHubTheme.border),
              ),
              child: Icon(Icons.search, size: 16, color: AgentHubTheme.textSecondary),
            ),
          ),
          const Spacer(),
          if (provider.currentTabIndex == 0 && provider.messages.isNotEmpty) ...[
            InkWell(
              onTap: () => provider.clearChatHistory(),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AgentHubTheme.cardBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AgentHubTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 14, color: AgentHubTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text('清空', style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 主题切换按钮
          InkWell(
            onTap: () => provider.toggleTheme(),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AgentHubTheme.cardBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgentHubTheme.border),
              ),
              child: Icon(
                provider.isDarkTheme ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 16,
                color: AgentHubTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 左侧边栏
  Widget _buildSidebar(BuildContext context, AppStateProvider provider) {
    return Container(
      width: 220,
      color: provider.isDarkTheme ? const Color(0xFF1E1E1E) : const Color(0xFFF2F0EB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebarHeader(provider),
          const SizedBox(height: 8),
          _buildNavItem(1, Icons.alarm_outlined, '定时任务', provider, badgeCount: provider.tasks.where((t) => t.isEnabled).length),
          _buildNavItem(2, Icons.extension_outlined, '插件', provider, badgeCount: provider.skills.length),
          _buildNavItem(3, Icons.settings_outlined, '设置', provider),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, thickness: 1, color: AgentHubTheme.divider),
          ),
          const SizedBox(height: 8),
          // 会话列表
          Expanded(child: _buildSessionList(provider)),
          _buildGatewayFooter(provider),
        ],
      ),
    );
  }

  /// 侧边栏头部：图标 + 状态信息
  Widget _buildSidebarHeader(AppStateProvider provider) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 10, top: 16, bottom: 8),
      child: Row(
        children: [
          // 使用 Material Icon 替代文本 'A'
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AgentHubTheme.pillBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.hub_outlined, size: 18, color: AgentHubTheme.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // 只显示状态信息，不再显示 'AgentHub'
              provider.config.modelName.isNotEmpty ? provider.config.modelName : '服务正常',
              style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.add, size: 18, color: AgentHubTheme.textSecondary),
            tooltip: '新建',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () async {
              await provider.createNewSession();
              provider.selectTab(0);
            },
          ),
        ],
      ),
    );
  }

  /// 导航项
  Widget _buildNavItem(int index, IconData icon, String label, AppStateProvider provider, {int? badgeCount}) {
    final isSelected = index == provider.currentTabIndex;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        onTap: () => provider.selectTab(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AgentHubTheme.primaryRedLight : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isSelected ? AgentHubTheme.primaryRed : AgentHubTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AgentHubTheme.primaryRed : AgentHubTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeCount != null && badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? AgentHubTheme.cardBackground : AgentHubTheme.pillBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSelected ? AgentHubTheme.primaryRed : AgentHubTheme.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 会话列表
  Widget _buildSessionList(AppStateProvider provider) {
    final sessions = provider.sessions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('会话', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AgentHubTheme.textSecondary)),
              const Spacer(),
              InkWell(
                onTap: () async {
                  await provider.createNewSession();
                  provider.selectTab(0);
                },
                child: Icon(Icons.add, size: 14, color: AgentHubTheme.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: sessions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('暂无会话', style: TextStyle(fontSize: 12, color: AgentHubTheme.textTertiary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final isActive = session.id == provider.activeSessionId && provider.currentTabIndex == 0;

                    return InkWell(
                      onTap: () {
                        provider.switchSession(session.id);
                        provider.selectTab(0);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: isActive ? AgentHubTheme.primaryRedLight : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.title,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive ? AgentHubTheme.primaryRed : AgentHubTheme.textPrimary,
                                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (isActive)
                              InkWell(
                                onTap: () => provider.deleteSession(session.id),
                                child: Icon(Icons.close, size: 14, color: AgentHubTheme.textTertiary),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 底部网关状态
  Widget _buildGatewayFooter(AppStateProvider provider) {
    final isOnline = provider.isGatewayOnline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgentHubTheme.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgentHubTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isOnline ? AgentHubTheme.statusGreen : AgentHubTheme.statusGray,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOnline ? '网关在线' : '网关未启动',
              style: TextStyle(fontSize: 11, color: AgentHubTheme.textSecondary),
            ),
          ),
          IconButton(
            icon: Icon(Icons.arrow_downward, size: 13, color: AgentHubTheme.textSecondary),
            tooltip: '隐藏',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => windowManager.hide(),
          ),
        ],
      ),
    );
  }
}

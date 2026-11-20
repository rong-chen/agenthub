import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';
import '../models/chat_message_model.dart';
import '../providers/app_state_provider.dart';
import '../services/claude_profile_service.dart';
import '../services/wechat_channel_service.dart';
import '../theme/agenthub_theme.dart';
import 'chat_view.dart';
import 'claude_manager_view.dart';
import 'tasks_view.dart';
import 'skills_view.dart';
import 'settings_view.dart';
import 'trash_view.dart';
import 'panels/file_diff_panel.dart';

/// 主窗口布局，包含左侧边栏与主工作区
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with WindowListener {
  bool _isSidebarCollapsed = false;
  double? _rightPanelWidth;
  bool _isDraggingDivider = false;

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
    AgentHubTheme.isDark = provider.isDarkTheme;

    final isChatTab = provider.currentTabIndex == 0;

    return Scaffold(
      backgroundColor: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final mainAreaWidth = !_isSidebarCollapsed ? (totalWidth - 221.0) : totalWidth;

          final minRightWidth = 320.0;
          final minChatWidth = 360.0;
          final maxRightWidth = max(minRightWidth, mainAreaWidth - minChatWidth);

          if (_rightPanelWidth == null) {
            _rightPanelWidth = (mainAreaWidth * 0.55).clamp(minRightWidth, maxRightWidth);
          } else {
            _rightPanelWidth = _rightPanelWidth!.clamp(minRightWidth, maxRightWidth);
          }

          return Row(
            children: [
              // 第一栏：左侧菜单栏
              if (!_isSidebarCollapsed) ...[
                _buildSidebar(context, provider),
                VerticalDivider(width: 1, thickness: 1, color: AgentHubTheme.divider),
              ],
              // 第二栏：中间会话/主工作区
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
                          ClaudeManagerView(),
                          TasksView(),
                          SkillsView(),
                          SettingsView(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 中间与右侧拖拽调节手柄及第三栏
              if (isChatTab) ...[
                _buildDraggableDivider(minRightWidth, maxRightWidth),
                SizedBox(
                  width: _rightPanelWidth,
                  child: _buildRightPanel(context, provider),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 构建可左右拖动调整宽度的分栏分隔条
  Widget _buildDraggableDivider(double minWidth, double maxWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _isDraggingDivider = true),
        onHorizontalDragUpdate: (details) {
          setState(() {
            _rightPanelWidth = (_rightPanelWidth! - details.delta.dx).clamp(minWidth, maxWidth);
          });
        },
        onHorizontalDragEnd: (_) => setState(() => _isDraggingDivider = false),
        child: Container(
          width: 7,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: _isDraggingDivider ? 2 : 1,
              height: double.infinity,
              color: _isDraggingDivider ? AgentHubTheme.primaryRed : AgentHubTheme.divider,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建右侧内容区域（长显，支持文件修改及后续扩展）
  Widget _buildRightPanel(BuildContext context, AppStateProvider provider) {
    final activeSession = provider.activeSession;
    final ckpt = provider.currentDisplayCheckpoint;

    return FileDiffPanel(
      checkpoint: ckpt,
      session: activeSession,
      message: provider.activeDiffMessage,
    );
  }

  /// 会话重命名弹窗
  void _showRenameDialog(BuildContext context, AppStateProvider provider, String sessionId, String currentTitle) {
    final titleCtrl = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AgentHubTheme.cardBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AgentHubTheme.border)),
          title: Text('重命名会话', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 380,
            child: TextField(
              controller: titleCtrl,
              autofocus: true,
              style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: AgentHubTheme.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AgentHubTheme.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AgentHubTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AgentHubTheme.primaryRed)),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  provider.renameSession(sessionId, val.trim());
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: AgentHubTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final text = titleCtrl.text.trim();
                if (text.isNotEmpty) {
                  provider.renameSession(sessionId, text);
                  Navigator.of(ctx).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AgentHubTheme.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  /// 弹出新建会话模式选择弹窗
  void _showCreateSessionDialog(BuildContext context, AppStateProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AgentHubTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AgentHubTheme.border),
          ),
          title: Text(
            '新建会话模式',
            style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await provider.createNewSession(sessionMode: 'chat');
                  provider.selectTab(0);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AgentHubTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AgentHubTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AgentHubTheme.cardBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.chat_bubble_outline, color: AgentHubTheme.primaryRed, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('聊天模式', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('标准智能问答交互', style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: AgentHubTheme.textTertiary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () async {
                  Navigator.of(ctx).pop();
                  String? selectedPath;
                  try {
                    final uri = await FilePicker.pickDirectory(dialogTitle: '选择工作目录');
                    selectedPath = uri?.toFilePath();
                  } catch (e) {
                    debugPrint('选择目录失败: $e');
                  }
                  if (selectedPath == null || selectedPath.isEmpty) return;

                  var cleanPath = selectedPath.trim();
                  while ((cleanPath.endsWith('/') || cleanPath.endsWith(r'\')) && cleanPath.length > 1) {
                    cleanPath = cleanPath.substring(0, cleanPath.length - 1);
                  }
                  final parts = cleanPath.split(Platform.pathSeparator);
                  final dirName = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : '工程目录';
                  final profiles = await ClaudeProfileService.instance.loadProfiles();
                  final profileId = profiles.isNotEmpty ? profiles.first.id : null;

                  await provider.createNewSession(
                    sessionMode: 'code',
                    workDir: cleanPath,
                    profileId: profileId,
                    title: '代码 - $dirName',
                  );
                  provider.selectTab(0);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AgentHubTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AgentHubTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AgentHubTheme.cardBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.terminal_outlined, color: AgentHubTheme.primaryRed, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('代码模式', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('绑定独立 Claude Code 实例，基于指定目录改代码', style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: AgentHubTheme.textTertiary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('取消', style: TextStyle(color: AgentHubTheme.textSecondary)),
            ),
          ],
        );
      },
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

  /// 微信通道管理与扫码弹窗
  void _showWechatChannelDialog(BuildContext context, AppStateProvider provider) {
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AgentHubTheme.border),
              ),
              title: Row(
                children: [
                  Icon(Icons.forum_outlined, size: 20, color: const Color(0xFF07C160)),
                  const SizedBox(width: 8),
                  Text(
                    '微信通道接入',
                    style: TextStyle(
                      color: AgentHubTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isRunning
                          ? AgentHubTheme.statusGreen
                          : (isWaitingScan ? AgentHubTheme.primaryRed : AgentHubTheme.statusGray),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isRunning
                        ? '已连接'
                        : (isWaitingScan ? '等待扫码' : (isGettingQr ? '获取二维码' : '未连接')),
                    style: TextStyle(
                      fontSize: 12,
                      color: isRunning ? AgentHubTheme.statusGreen : AgentHubTheme.textTertiary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '启用微信通道',
                          style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13),
                        ),
                        const Spacer(),
                        Switch(
                          value: p.config.wechatChannelEnabled,
                          activeThumbColor: const Color(0xFF07C160),
                          onChanged: (val) async {
                            await p.toggleWechatChannel(val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '微信消息自动回复',
                          style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13),
                        ),
                        const Spacer(),
                        Switch(
                          value: p.config.wechatAutoReply,
                          activeThumbColor: const Color(0xFF07C160),
                          onChanged: (val) async {
                            await p.setWechatAutoReply(val);
                          },
                        ),
                      ],
                    ),
                    Divider(height: 20, color: AgentHubTheme.divider),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AgentHubTheme.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AgentHubTheme.border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isGettingQr) ...[
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '正在请求微信登录二维码...',
                              style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12),
                            ),
                          ] else if (isWaitingScan && wechat.qrCodeText != null && wechat.qrCodeText!.isNotEmpty) ...[
                            Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: QrImageView(
                                data: wechat.qrCodeText!,
                                version: QrVersions.auto,
                                size: 160.0,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '请使用微信扫描上方二维码确认登录',
                              style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '有效时间还剩 ${wechat.qrCodeRemainingSeconds} 秒',
                              style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 11),
                            ),
                          ] else if (isRunning) ...[
                            Icon(Icons.check_circle_outline, size: 36, color: AgentHubTheme.statusGreen),
                            const SizedBox(height: 8),
                            Text(
                              '已成功接入微信',
                              style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '账号: ${wechat.accountName ?? "微信用户"}',
                              style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12),
                            ),
                          ] else ...[
                            Icon(Icons.qr_code_2_outlined, size: 40, color: AgentHubTheme.textTertiary),
                            const SizedBox(height: 8),
                            Text(
                              p.config.wechatChannelEnabled
                                  ? (wechat.lastError ?? '请点击下方按钮获取最新二维码')
                                  : '微信通道当前未启用，开启上方开关即可开始接入',
                              style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
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
          // 微信通道快捷入口
          InkWell(
            onTap: () => _showWechatChannelDialog(context, provider),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: AgentHubTheme.cardBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AgentHubTheme.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 15,
                    color: provider.wechatService.isRunning
                        ? const Color(0xFF07C160)
                        : AgentHubTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    provider.wechatService.isRunning ? '微信在线' : '微信通道',
                    style: TextStyle(
                      fontSize: 11,
                      color: provider.wechatService.isRunning
                          ? const Color(0xFF07C160)
                          : AgentHubTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
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
          if (provider.currentTabIndex == 0) ...[
            const SizedBox(width: 8),
            // 右侧面板开关
            InkWell(
              onTap: () {
                if (provider.rightPanelType != RightPanelType.none) {
                  provider.closeRightPanel();
                } else {
                  // 找到当前会话最近的一个带 checkpoint 的消息
                  final lastCkptMsg = provider.messages.reversed
                      .cast<ChatMessageModel?>()
                      .firstWhere((m) => m?.checkpoint != null, orElse: () => null);
                  if (lastCkptMsg?.checkpoint != null) {
                    provider.openFileDiffPanel(lastCkptMsg!.checkpoint!, lastCkptMsg);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('当前会话暂无文件修改记录'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: provider.rightPanelType != RightPanelType.none
                      ? AgentHubTheme.primaryRed.withValues(alpha: 0.1)
                      : AgentHubTheme.cardBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: provider.rightPanelType != RightPanelType.none
                        ? AgentHubTheme.primaryRed
                        : AgentHubTheme.border,
                  ),
                ),
                child: Icon(
                  Icons.vertical_split_outlined,
                  size: 16,
                  color: provider.rightPanelType != RightPanelType.none
                      ? AgentHubTheme.primaryRed
                      : AgentHubTheme.textSecondary,
                ),
              ),
            ),
          ],
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
          _buildNavItem(
            1,
            Icons.terminal_outlined,
            'Claude 工作台',
            provider,
          ),
          _buildNavItem(
            2,
            Icons.alarm_outlined,
            '定时任务',
            provider,
            badgeCount: provider.tasks.where((t) => t.isEnabled).length,
          ),
          _buildNavItem(
            3,
            Icons.extension_outlined,
            '插件',
            provider,
            badgeCount: provider.skills.length,
          ),
          _buildNavItem(4, Icons.settings_outlined, '设置', provider),
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
            onPressed: () => _showCreateSessionDialog(context, provider),
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
              const SizedBox(width: 6),
              if (provider.totalUnreadCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AgentHubTheme.primaryRed,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '未读 ${provider.totalUnreadCount}',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrashView()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.delete_outline, size: 14, color: AgentHubTheme.textTertiary),
                ),
              ),
              InkWell(
                onTap: () => _showCreateSessionDialog(context, provider),
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
                    final isActive = session.id == provider.activeSessionId;
                    final isWechat = session.channel == 'wechat';
                    final unread = session.unreadCount;

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
                            Icon(
                              isWechat
                                  ? Icons.forum_outlined
                                  : (session.isCodeMode ? Icons.terminal_outlined : Icons.chat_bubble_outline),
                              size: 13,
                              color: isWechat
                                  ? const Color(0xFF07C160)
                                  : (isActive ? AgentHubTheme.primaryRed : AgentHubTheme.textSecondary),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Row(
                                children: [
                                  if (session.isCodeMode) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      margin: const EdgeInsets.only(right: 4),
                                      decoration: BoxDecoration(
                                        color: isActive ? AgentHubTheme.primaryRed : AgentHubTheme.border,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        '代码',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isActive ? Colors.white : AgentHubTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
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
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (provider.isSessionBusy(session.id)) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AgentHubTheme.primaryRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '运行中',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: AgentHubTheme.primaryRed,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            // 图标与名称右侧：未读数量角标（选中时不显示已读字样）
                            if (unread > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AgentHubTheme.primaryRed,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else if (!isActive)
                              Text(
                                '已读',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AgentHubTheme.textTertiary,
                                ),
                              ),
                            if (isActive) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _showRenameDialog(context, provider, session.id, session.title),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.edit_outlined, size: 13, color: AgentHubTheme.textTertiary),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  provider.deleteSession(session.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('会话已移入回收站，7天后自动清理'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Icon(Icons.close, size: 14, color: AgentHubTheme.textTertiary),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_session_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/agenthub_theme.dart';

/// 会话回收站界面
class TrashView extends StatefulWidget {
  const TrashView({super.key});

  @override
  State<TrashView> createState() => _TrashViewState();
}

class _TrashViewState extends State<TrashView> {
  List<ChatSessionModel> _deletedSessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeletedList();
  }

  Future<void> _loadDeletedList() async {
    setState(() => _isLoading = true);
    final provider = context.read<AppStateProvider>();
    final list = await provider.loadDeletedSessions();
    if (mounted) {
      setState(() {
        _deletedSessions = list;
        _isLoading = false;
      });
    }
  }

  /// 恢复指定会话
  Future<void> _handleRestore(String sessionId) async {
    final provider = context.read<AppStateProvider>();
    await provider.restoreSession(sessionId);
    await _loadDeletedList();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复会话')),
      );
    }
  }

  /// 彻底物理删除指定会话
  Future<void> _handleHardDelete(String sessionId) async {
    final provider = context.read<AppStateProvider>();
    await provider.hardDeleteSession(sessionId);
    await _loadDeletedList();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已彻底删除会话')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentHubTheme.background,
      appBar: AppBar(
        title: Text('会话回收站', style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16)),
        backgroundColor: AgentHubTheme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AgentHubTheme.textPrimary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedSessions.isEmpty
              ? Center(
                  child: Text(
                    '回收站为空，7 天后超期的已删会话将被自动彻底清理',
                    style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _deletedSessions.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AgentHubTheme.divider),
                  itemBuilder: (context, index) {
                    final item = _deletedSessions[index];
                    final delDate = item.deletedAt != null
                        ? '${item.deletedAt!.month}月${item.deletedAt!.day}日 ${item.deletedAt!.hour.toString().padLeft(2, '0')}:${item.deletedAt!.minute.toString().padLeft(2, '0')}'
                        : '未知时间';

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: AgentHubTheme.textSecondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '删除时间: $delDate',
                                  style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _handleRestore(item.id),
                            icon: const Icon(Icons.restore, size: 14),
                            label: const Text('恢复', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: AgentHubTheme.primaryRed,
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _handleHardDelete(item.id),
                            icon: const Icon(Icons.delete_forever_outlined, size: 14),
                            label: const Text('彻底删除', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: AgentHubTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

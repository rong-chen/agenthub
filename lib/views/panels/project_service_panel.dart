import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/project_service_manager.dart';
import '../../theme/agenthub_theme.dart';

/// 项目本地服务运行与日志控制台面板
class ProjectServicePanel extends StatefulWidget {
  final String sessionId;
  final String workDir;
  final VoidCallback? onClose;

  const ProjectServicePanel({
    super.key,
    required this.sessionId,
    required this.workDir,
    this.onClose,
  });

  @override
  State<ProjectServicePanel> createState() => _ProjectServicePanelState();
}

class _ProjectServicePanelState extends State<ProjectServicePanel> {
  final TextEditingController _cmdController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ProjectServiceManager _serviceManager = ProjectServiceManager.instance;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    final inst = _serviceManager.getOrCreateInstance(widget.sessionId, widget.workDir);
    _cmdController.text = inst.command;
    _serviceManager.addListener(_onServiceUpdate);
  }

  @override
  void didUpdateWidget(covariant ProjectServicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId || oldWidget.workDir != widget.workDir) {
      final inst = _serviceManager.getOrCreateInstance(widget.sessionId, widget.workDir);
      _cmdController.text = inst.command;
    }
  }

  @override
  void dispose() {
    _serviceManager.removeListener(_onServiceUpdate);
    _cmdController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 监听日志或状态变化并自动滚动
  void _onServiceUpdate() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  /// 启动服务
  void _start() {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;
    _serviceManager.startService(widget.sessionId, widget.workDir, cmd);
  }

  /// 停止服务
  void _stop() {
    _serviceManager.stopService(widget.sessionId);
  }

  /// 重启服务
  void _restart() {
    _serviceManager.restartService(widget.sessionId);
  }

  /// 清空日志
  void _clearLogs() {
    _serviceManager.clearLogs(widget.sessionId);
  }

  /// 复制全部日志
  void _copyAllLogs() {
    final inst = _serviceManager.getInstance(widget.sessionId);
    if (inst == null || inst.logs.isEmpty) return;
    final text = inst.logs.map((l) => l.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制全部控制台日志'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AgentHubTheme.isDark;
    final inst = _serviceManager.getOrCreateInstance(widget.sessionId, widget.workDir);
    final isRunning = inst.status == ServiceStatus.running;
    final isStarting = inst.status == ServiceStatus.starting;
    final isStopping = inst.status == ServiceStatus.stopping;

    return Container(
      color: isDark ? const Color(0xFF121417) : const Color(0xFFF6F8FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 操作工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1E22) : Colors.white,
              border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
            ),
            child: Row(
              children: [
                // 命令输入框
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF26292F) : const Color(0xFFF0F2F5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AgentHubTheme.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(Icons.terminal, size: 14, color: AgentHubTheme.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _cmdController,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AgentHubTheme.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              hintText: '输入启动命令，例如 npm run dev 或 python3 main.py',
                              hintStyle: TextStyle(fontSize: 11),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            enabled: !isRunning && !isStarting && !isStopping,
                            onSubmitted: (_) => _start(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 启动 / 停止 按钮
                if (!isRunning && !isStarting) ...[
                  ElevatedButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow, size: 15),
                    label: const Text('启动', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EA44F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 0,
                    ),
                  ),
                ] else ...[
                  // 停止按钮
                  ElevatedButton.icon(
                    onPressed: isStopping ? null : _stop,
                    icon: const Icon(Icons.stop, size: 15),
                    label: Text(isStopping ? '停止中' : '停止', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCF222E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 重启按钮
                  OutlinedButton(
                    onPressed: isStopping ? null : _restart,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AgentHubTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      minimumSize: const Size(0, 32),
                      side: BorderSide(color: AgentHubTheme.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Icon(Icons.refresh, size: 14),
                  ),
                ],
              ],
            ),
          ),

          // 状态与日志控制栏
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181A1E) : const Color(0xFFEBEFF4),
              border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
            ),
            child: Row(
              children: [
                // 状态指示器
                _buildStatusBadge(inst.status, inst.pid),
                const Spacer(),
                // 自动滚动开关
                InkWell(
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          _autoScroll ? Icons.arrow_downward : Icons.pause_circle_outline,
                          size: 13,
                          color: _autoScroll ? const Color(0xFF2EA44F) : AgentHubTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _autoScroll ? '自动滚动' : '暂停滚动',
                          style: TextStyle(
                            fontSize: 11,
                            color: _autoScroll ? const Color(0xFF2EA44F) : AgentHubTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 复制日志
                IconButton(
                  onPressed: _copyAllLogs,
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: '复制全部日志',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: AgentHubTheme.textSecondary,
                ),
                const SizedBox(width: 8),
                // 清空日志
                IconButton(
                  onPressed: _clearLogs,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                  tooltip: '清空控制台日志',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: AgentHubTheme.textSecondary,
                ),
              ],
            ),
          ),

          // 日志控制台主体
          Expanded(
            child: inst.logs.isEmpty
                ? _buildEmptyState(isDark)
                : Container(
                    color: isDark ? const Color(0xFF0D1117) : const Color(0xFF1E1E1E),
                    child: SelectionArea(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: inst.logs.length,
                        itemBuilder: (context, index) {
                          final log = inst.logs[index];
                          return _buildLogItem(log);
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 状态胶囊标签
  Widget _buildStatusBadge(ServiceStatus status, int? pid) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case ServiceStatus.running:
        bg = const Color(0xFF2EA44F).withValues(alpha: 0.15);
        fg = const Color(0xFF2EA44F);
        label = pid != null ? '运行中 PID: $pid' : '运行中';
        break;
      case ServiceStatus.starting:
        bg = const Color(0xFF0969DA).withValues(alpha: 0.15);
        fg = const Color(0xFF0969DA);
        label = '启动中...';
        break;
      case ServiceStatus.stopping:
        bg = const Color(0xFFD29922).withValues(alpha: 0.15);
        fg = const Color(0xFFD29922);
        label = '停止中...';
        break;
      case ServiceStatus.error:
        bg = const Color(0xFFCF222E).withValues(alpha: 0.15);
        fg = const Color(0xFFCF222E);
        label = '异常退出';
        break;
      case ServiceStatus.stopped:
        bg = AgentHubTheme.border;
        fg = AgentHubTheme.textSecondary;
        label = '未运行';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  /// 单条控制台日志行渲染
  Widget _buildLogItem(ServiceLogLine log) {
    final timeStr =
        '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[$timeStr] ',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF6E7681),
            ),
          ),
          Expanded(
            child: Text(
              log.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.35,
                color: log.isError ? const Color(0xFFF85149) : const Color(0xFFE6EDF3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 空日志占位引导
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal_outlined,
              size: 44,
              color: isDark ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 12),
            Text(
              '服务控制台就绪',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AgentHubTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '在上方输入启动命令并点击启动，服务将在后台持续运行并实时输出日志。',
              style: TextStyle(
                fontSize: 12,
                color: AgentHubTheme.textTertiary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

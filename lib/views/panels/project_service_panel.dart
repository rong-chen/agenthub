import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/tool_step_model.dart';
import '../../providers/app_state_provider.dart';
import '../../services/project_service_manager.dart';
import '../../theme/agenthub_theme.dart';

/// 命令与后台服务运行日志控制台面板
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
  final ScrollController _scrollController = ScrollController();
  final ProjectServiceManager _serviceManager = ProjectServiceManager.instance;
  bool _autoScroll = true;
  bool _viewBackgroundService = false;

  @override
  void initState() {
    super.initState();
    _serviceManager.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _serviceManager.removeListener(_onUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottomIfNeeded();
  }

  void _scrollToBottomIfNeeded() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  /// 复制日志
  void _copyLogs(String content) {
    if (content.isEmpty) return;
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制控制台日志'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AgentHubTheme.isDark;
    final provider = context.watch<AppStateProvider>();
    final allCmdSteps = provider.currentSessionCommandSteps;

    // 优先取选中的命令步骤，否则取当前会话最新一条命令步骤
    final activeStep = provider.activeConsoleStep ?? (allCmdSteps.isNotEmpty ? allCmdSteps.last : null);

    // 查询当前项目的后台常驻服务实例
    final bgInstance = _serviceManager.getInstance(widget.sessionId);
    final hasRunningBgService = bgInstance != null && bgInstance.status == ServiceStatus.running;

    // 如果没有点击特定命令但有运行中的后台服务，自动查看后台服务
    final showBgService = _viewBackgroundService || (activeStep == null && hasRunningBgService);

    return Container(
      color: isDark ? const Color(0xFF0E1117) : const Color(0xFF1E1E1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部控制与命令选择栏
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFF252526),
              border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
            ),
            child: Row(
              children: [
                // 终端图标与当前展示命令
                Icon(Icons.terminal, size: 15, color: AgentHubTheme.primaryRed),
                const SizedBox(width: 8),
                Expanded(
                  child: showBgService && bgInstance != null
                      ? Text(
                          '> ${bgInstance.command} (后台服务)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : activeStep != null
                          ? Text(
                              '> ${activeStep.target.isNotEmpty ? activeStep.target : activeStep.actionLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              '暂无命令输出',
                              style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary),
                            ),
                ),
                const SizedBox(width: 8),

                // 状态胶囊
                if (showBgService && bgInstance != null) ...[
                  _buildStatusPill('运行中 PID: ${bgInstance.pid ?? ''}', const Color(0xFF2EA44F)),
                ] else if (activeStep != null) ...[
                  _buildStepStatusPill(activeStep.status),
                ],

                const SizedBox(width: 8),

                // 如果有后台服务，显示切换药丸
                if (hasRunningBgService) ...[
                  InkWell(
                    onTap: () {
                      setState(() {
                        _viewBackgroundService = !_viewBackgroundService;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: showBgService
                            ? const Color(0xFF2EA44F).withValues(alpha: 0.2)
                            : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFF333333)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: showBgService ? const Color(0xFF2EA44F) : AgentHubTheme.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2EA44F),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            showBgService ? '查看命令' : '开发服务',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // 自动滚动开关
                InkWell(
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      _autoScroll ? Icons.arrow_downward : Icons.pause_circle_outline,
                      size: 15,
                      color: _autoScroll ? const Color(0xFF2EA44F) : AgentHubTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 复制全部日志
                IconButton(
                  onPressed: () {
                    if (showBgService && bgInstance != null) {
                      final content = bgInstance.logs.map((l) => l.text).join('\n');
                      _copyLogs(content);
                    } else if (activeStep != null) {
                      _copyLogs(activeStep.output ?? activeStep.input ?? '');
                    }
                  },
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: '复制控制台日志',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: AgentHubTheme.textSecondary,
                ),
              ],
            ),
          ),

          // 终端主体区域
          Expanded(
            child: showBgService && bgInstance != null
                ? _buildBgServiceLogs(bgInstance)
                : activeStep != null
                    ? _buildStepLogs(activeStep)
                    : _buildEmptyState(isDark),
          ),
        ],
      ),
    );
  }

  /// 状态小胶囊
  Widget _buildStatusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 步骤状态小胶囊
  Widget _buildStepStatusPill(ToolStepStatus status) {
    switch (status) {
      case ToolStepStatus.running:
        return _buildStatusPill('执行中...', const Color(0xFF0969DA));
      case ToolStepStatus.success:
        return _buildStatusPill('已完成', const Color(0xFF2EA44F));
      case ToolStepStatus.error:
        return _buildStatusPill('执行失败', const Color(0xFFCF222E));
    }
  }

  /// 渲染后台开发服务的流式日志
  Widget _buildBgServiceLogs(ProjectServiceInstance inst) {
    if (inst.logs.isEmpty) {
      return const Center(
        child: Text(
          '后台开发服务已就绪，等待服务产生实时输出...',
          style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
        ),
      );
    }

    return SelectionArea(
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: inst.logs.length,
        itemBuilder: (context, index) {
          final log = inst.logs[index];
          final timeStr =
              '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
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
        },
      ),
    );
  }

  /// 渲染单条命令步骤的执行日志
  Widget _buildStepLogs(ToolStepModel step) {
    final rawOutput = step.output;
    final isRunning = step.status == ToolStepStatus.running;
    final timeStr =
        '${step.timestamp.hour.toString().padLeft(2, '0')}:${step.timestamp.minute.toString().padLeft(2, '0')}:${step.timestamp.second.toString().padLeft(2, '0')}';

    return SelectionArea(
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(14),
        children: [
          // 命令行头信息
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '执行命令: ',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF8B949E),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        step.target.isNotEmpty ? step.target : (step.input ?? ''),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF58A6FF),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '发起时间: $timeStr | 状态: ${step.status == ToolStepStatus.running ? "执行中" : (step.status == ToolStepStatus.success ? "成功" : "失败")}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF6E7681),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 执行日志输出
          if (rawOutput != null && rawOutput.trim().isNotEmpty) ...[
            Text(
              rawOutput,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.4,
                color: step.status == ToolStepStatus.error
                    ? const Color(0xFFF85149)
                    : const Color(0xFFE6EDF3),
              ),
            ),
          ] else if (isRunning) ...[
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF58A6FF)),
                ),
                const SizedBox(width: 8),
                const Text(
                  '命令正在后台执行中，等待输出流...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: Color(0xFF8B949E),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text(
              '命令执行完成，无标准输出。',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: Color(0xFF6E7681),
              ),
            ),
          ],

          if (isRunning) ...[
            const SizedBox(height: 6),
            const Text(
              '▋',
              style: TextStyle(
                color: Color(0xFF58A6FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 空态
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
              '命令控制台就绪',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AgentHubTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '在左侧会话中点击任意命令步骤，即可在此查看该命令的执行日志；长期运行的开发服务将在此持续流式输出。',
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

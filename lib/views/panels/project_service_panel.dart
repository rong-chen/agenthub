import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/tool_step_model.dart';
import '../../providers/app_state_provider.dart';
import '../../services/project_service_manager.dart';

/// 沉浸式命令行与后台服务控制台面板
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

  Timer? _taskLogPollTimer;
  String? _trackedOutputPath;
  String? _trackedOutputContent;

  @override
  void initState() {
    super.initState();
    _serviceManager.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _taskLogPollTimer?.cancel();
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

  /// 检查步骤输出中是否包含 Claude 后台任务日志重定向文件并持续轮询读取
  void _checkAndTrackTaskOutputFile(ToolStepModel? step) {
    if (step == null || step.output == null) {
      if (_trackedOutputPath != null) _stopTaskLogPolling();
      return;
    }

    final match = RegExp(r'Output is being written to:\s*([^\s\r\n]+\.output)').firstMatch(step.output!);
    if (match != null) {
      final path = match.group(1)?.trim();
      if (path != null && path.isNotEmpty && path != _trackedOutputPath) {
        _trackedOutputPath = path;
        _startTaskLogPolling(path);
      }
    } else if (_trackedOutputPath != null) {
      _stopTaskLogPolling();
    }
  }

  void _startTaskLogPolling(String filePath) {
    _taskLogPollTimer?.cancel();
    _readTaskOutputFile(filePath);
    _taskLogPollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _readTaskOutputFile(filePath);
    });
  }

  void _stopTaskLogPolling() {
    _taskLogPollTimer?.cancel();
    _taskLogPollTimer = null;
    _trackedOutputPath = null;
    _trackedOutputContent = null;
  }

  Future<void> _readTaskOutputFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted && content != _trackedOutputContent) {
          setState(() {
            _trackedOutputContent = content;
          });
          _scrollToBottomIfNeeded();
        }
      }
    } catch (_) {}
  }

  /// 复制日志
  void _copyLogs(String content) {
    if (content.isEmpty) return;
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制终端日志'), duration: Duration(seconds: 1)),
    );
  }

  /// 构建支持点击打开 URL 的富文本 TextSpan
  List<InlineSpan> _buildLinkifiedSpans(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final urlRegex = RegExp(r'''(https?://[^\s'"()<>\uFF08\uFF09]+)''');

    int lastIndex = 0;
    for (final match in urlRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      final url = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  try {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } catch (_) {}
                }
              },
              child: Text(
                url,
                style: baseStyle.copyWith(
                  color: const Color(0xFF58A6FF),
                  decoration: TextDecoration.underline,
                  decorationColor: const Color(0xFF58A6FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final allCmdSteps = provider.currentSessionCommandSteps;

    // 优先取选中的命令步骤，否则取当前会话最新一条命令步骤
    final activeStep = provider.activeConsoleStep ?? (allCmdSteps.isNotEmpty ? allCmdSteps.last : null);
    _checkAndTrackTaskOutputFile(activeStep);

    // 查询当前项目的后台常驻服务实例
    final bgInstance = _serviceManager.getInstance(widget.sessionId);
    final hasRunningBgService = bgInstance != null && bgInstance.status == ServiceStatus.running;

    // 是否显示后台管理服务
    final showBgService = activeStep == null && hasRunningBgService;
    final isTrackedBgTask = _trackedOutputContent != null;

    final dirName = widget.workDir.isNotEmpty ? p.basename(widget.workDir) : 'terminal';

    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 终端顶部控制栏
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
            ),
            child: Row(
              children: [
                // 经典终端红黄绿圆点装饰
                Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 9, height: 9, decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle)),
                const SizedBox(width: 12),

                // 终端标签名
                Icon(Icons.terminal, size: 14, color: const Color(0xFF8B949E)),
                const SizedBox(width: 6),
                Text(
                  dirName,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC9D1D9),
                  ),
                ),
                const Spacer(),

                // 状态指示
                if (showBgService) ...[
                  _buildStatusDot('运行中 PID: ${bgInstance.pid ?? ""}', const Color(0xFF2EA44F)),
                ] else if (isTrackedBgTask) ...[
                  _buildStatusDot('开发服务运行中', const Color(0xFF2EA44F)),
                ] else if (activeStep != null) ...[
                  _buildStepStatusDot(activeStep.status),
                ],

                const SizedBox(width: 8),

                // 自动滚动开关
                InkWell(
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      _autoScroll ? Icons.arrow_downward : Icons.pause_circle_outline,
                      size: 14,
                      color: _autoScroll ? const Color(0xFF2EA44F) : const Color(0xFF8B949E),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 复制日志
                IconButton(
                  onPressed: () {
                    if (showBgService) {
                      final content = bgInstance.logs.map((l) => l.text).join('\n');
                      _copyLogs(content);
                    } else if (isTrackedBgTask && _trackedOutputContent != null) {
                      _copyLogs(_trackedOutputContent!);
                    } else if (activeStep != null) {
                      _copyLogs(activeStep.output ?? activeStep.input ?? '');
                    }
                  },
                  icon: const Icon(Icons.copy, size: 13),
                  tooltip: '复制控制台内容',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: const Color(0xFF8B949E),
                ),
              ],
            ),
          ),

          // 终端输出主体区
          Expanded(
            child: showBgService
                ? _buildBgServiceTerminal(bgInstance, dirName)
                : activeStep != null
                    ? _buildStepTerminal(activeStep, dirName)
                    : _buildEmptyTerminal(dirName),
          ),
        ],
      ),
    );
  }

  /// 状态小点
  Widget _buildStatusDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 步骤状态小点
  Widget _buildStepStatusDot(ToolStepStatus status) {
    switch (status) {
      case ToolStepStatus.running:
        return _buildStatusDot('执行中...', const Color(0xFF0969DA));
      case ToolStepStatus.success:
        return _buildStatusDot('成功', const Color(0xFF2EA44F));
      case ToolStepStatus.error:
        return _buildStatusDot('失败', const Color(0xFFCF222E));
    }
  }

  /// 渲染纯正命令行风格的单步骤终端
  Widget _buildStepTerminal(ToolStepModel step, String dirName) {
    final cmd = step.actualCommand.isNotEmpty ? step.actualCommand : step.target;
    final rawOutput = _trackedOutputContent ?? step.output;
    final isTrackedBg = _trackedOutputContent != null;
    final isRunning = step.status == ToolStepStatus.running || isTrackedBg;

    const baseTextStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.45,
      color: Color(0xFFC9D1D9),
    );

    return SelectionArea(
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(14),
        children: [
          // 命令行提示符: ➜ opencode $ npm run dev
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '➜ ',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2EA44F),
                ),
              ),
              Text(
                '$dirName ',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF58A6FF),
                ),
              ),
              const Text(
                '\$ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E),
                ),
              ),
              Expanded(
                child: Text(
                  cmd,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 输出内容（带自动 URL 识别与超链接交互）
          if (rawOutput != null && rawOutput.trim().isNotEmpty) ...[
            Text.rich(
              TextSpan(
                children: _buildLinkifiedSpans(
                  rawOutput,
                  step.status == ToolStepStatus.error && !isTrackedBg
                      ? baseTextStyle.copyWith(color: const Color(0xFFF85149))
                      : baseTextStyle,
                ),
              ),
            ),
          ] else if (isRunning) ...[
            const Text(
              '正在等待命令执行输出...',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF8B949E),
              ),
            ),
          ],

          if (isRunning) ...[
            const SizedBox(height: 4),
            const Text(
              '▋',
              style: TextStyle(
                color: Color(0xFF2EA44F),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 渲染纯正命令行风格的后台开发服务
  Widget _buildBgServiceTerminal(ProjectServiceInstance inst, String dirName) {
    const baseTextStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.45,
      color: Color(0xFFC9D1D9),
    );

    return SelectionArea(
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '➜ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2EA44F),
                ),
              ),
              Text(
                '$dirName ',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF58A6FF),
                ),
              ),
              const Text(
                '\$ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E),
                ),
              ),
              Expanded(
                child: Text(
                  inst.command,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (inst.logs.isNotEmpty) ...[
            ...inst.logs.map((log) {
              return Text.rich(
                TextSpan(
                  children: _buildLinkifiedSpans(
                    log.text,
                    log.isError
                        ? baseTextStyle.copyWith(color: const Color(0xFFF85149))
                        : baseTextStyle,
                  ),
                ),
              );
            }),
          ] else ...[
            const Text(
              '后台开发服务已就绪，正在接收输出流...',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF8B949E),
              ),
            ),
          ],

          if (inst.status == ServiceStatus.running) ...[
            const SizedBox(height: 4),
            const Text(
              '▋',
              style: TextStyle(
                color: Color(0xFF2EA44F),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 终端空态
  Widget _buildEmptyTerminal(String dirName) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '➜ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2EA44F),
                ),
              ),
              Text(
                '$dirName ',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF58A6FF),
                ),
              ),
              const Text(
                '\$ ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8B949E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '终端就绪。在左侧会话中点击任意命令，即可在此查看命令输出；点击网址链接可直接在浏览器中打开。',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFF6E7681),
            ),
          ),
        ],
      ),
    );
  }
}

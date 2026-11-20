import 'package:flutter/material.dart';
import '../../models/tool_step_model.dart';
import '../../theme/agenthub_theme.dart';

/// 工具调用步骤卡片组组件（忠实还原 Agent 执行步骤列表外观）
class ToolStepsCard extends StatefulWidget {
  final List<ToolStepModel> steps;

  const ToolStepsCard({super.key, required this.steps});

  @override
  State<ToolStepsCard> createState() => _ToolStepsCardState();
}

class _ToolStepsCardState extends State<ToolStepsCard> {
  final Set<String> _expandedStepIds = {};

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();

    // 智能将连续相同类型的步骤打包为批量卡片，其余保留为单步骤卡片
    final groupedCards = _groupSteps(widget.steps);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: groupedCards.map((group) {
          if (group.isBatch) {
            return _buildBatchCard(group);
          } else {
            return _buildSingleCard(group.step!);
          }
        }).toList(),
      ),
    );
  }

  /// 构建单工具调用步骤卡片
  Widget _buildSingleCard(ToolStepModel step) {
    final isDark = AgentHubTheme.isDark;
    final isExpanded = _expandedStepIds.contains(step.id);
    final isFileAction = step.actionLabel.contains('文件');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE4E4E6),
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedStepIds.remove(step.id);
            } else {
              _expandedStepIds.add(step.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _getToolIcon(step.actionLabel, step.target),
                  const SizedBox(width: 8),
                  Text(
                    step.actionLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AgentHubTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isFileAction && step.target.isNotEmpty) ...[
                    _buildFileChip(step.target),
                  ] else if (step.target.isNotEmpty) ...[
                    Expanded(
                      child: Text(
                        step.target,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AgentHubTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  _buildStatusDot(step.status),
                ],
              ),
              if (isExpanded && (step.input != null || step.output != null)) ...[
                const SizedBox(height: 8),
                Divider(height: 1, color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE4E4E6)),
                const SizedBox(height: 6),
                if (step.input != null && step.input!.trim().isNotEmpty) ...[
                  Text(
                    '输入参数: ${step.input}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AgentHubTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (step.output != null && step.output!.trim().isNotEmpty) ...[
                  Text(
                    '执行结果:\n${step.output}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: step.status == ToolStepStatus.error
                          ? const Color(0xFFCF222E)
                          : AgentHubTheme.textPrimary,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建批量工具调用步骤卡片
  Widget _buildBatchCard(_GroupedStepGroup group) {
    final isDark = AgentHubTheme.isDark;
    final subSteps = group.subSteps;
    final hasError = subSteps.any((s) => s.status == ToolStepStatus.error);
    final allDone = subSteps.every((s) => s.status == ToolStepStatus.success);
    final errorCount = subSteps.where((s) => s.status == ToolStepStatus.error).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE4E4E6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部摘要
            Row(
              children: [
                _getToolIcon(group.actionLabel, ''),
                const SizedBox(width: 8),
                Text(
                  '${_getBatchTitle(group.actionLabel)} (${subSteps.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AgentHubTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                if (hasError) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFCF222E)),
                      const SizedBox(width: 3),
                      Text(
                        '$errorCount 失败',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFCF222E),
                        ),
                      ),
                    ],
                  ),
                ] else if (allDone) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check, size: 14, color: Color(0xFF2EA44F)),
                      SizedBox(width: 3),
                      Text(
                        '全部完成',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2EA44F),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    '进行中...',
                    style: TextStyle(fontSize: 12, color: AgentHubTheme.textSecondary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // 树形子步骤列表
            Stack(
              children: [
                // 树状连接纵线
                Positioned(
                  left: 17,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 1.5,
                    color: isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
                  ),
                ),
                Column(
                  children: subSteps.map((child) {
                    final isPy = child.target.endsWith('.py');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          // 子节点图标或圆点
                          if (isPy) ...[
                            Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3572A5).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'Py',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3572A5),
                                ),
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              child.target.isNotEmpty ? child.target : child.actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AgentHubTheme.textPrimary,
                              ),
                            ),
                          ),
                          _buildStatusDot(child.status),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 状态小圆点
  Widget _buildStatusDot(ToolStepStatus status) {
    Color color;
    switch (status) {
      case ToolStepStatus.success:
        color = const Color(0xFF2EA44F);
        break;
      case ToolStepStatus.error:
        color = const Color(0xFFCF222E);
        break;
      case ToolStepStatus.running:
        color = const Color(0xFF0969DA);
        break;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: status == ToolStepStatus.running
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  /// 文件徽章芯片
  Widget _buildFileChip(String fileName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0969DA).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 11, color: Color(0xFF0969DA)),
          const SizedBox(width: 4),
          Text(
            fileName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0969DA),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取工具图标
  Widget _getToolIcon(String actionLabel, String target) {
    if (actionLabel.contains('命令') || actionLabel.contains('bash') || actionLabel.contains('exec')) {
      return Icon(Icons.terminal_outlined, size: 15, color: AgentHubTheme.textSecondary);
    }
    if (actionLabel.contains('读取') || actionLabel.contains('read')) {
      return Icon(Icons.description_outlined, size: 15, color: AgentHubTheme.textSecondary);
    }
    if (actionLabel.contains('创建') || actionLabel.contains('写入') || actionLabel.contains('write')) {
      return Icon(Icons.note_add_outlined, size: 15, color: AgentHubTheme.textSecondary);
    }
    if (actionLabel.contains('编辑') || actionLabel.contains('edit')) {
      return Icon(Icons.edit_note_outlined, size: 16, color: AgentHubTheme.textSecondary);
    }
    return Icon(Icons.tune, size: 15, color: AgentHubTheme.textSecondary);
  }

  /// 获取批量标题
  String _getBatchTitle(String actionLabel) {
    if (actionLabel.contains('命令')) return '批量运行命令';
    if (actionLabel.contains('读取')) return '批量读取文件';
    if (actionLabel.contains('文件')) return '批量处理文件';
    return '批量$actionLabel';
  }

  /// 将连续相同类型的工具调用自动打组为批量卡片
  List<_GroupedStepGroup> _groupSteps(List<ToolStepModel> steps) {
    final List<_GroupedStepGroup> result = [];
    int i = 0;
    while (i < steps.length) {
      final current = steps[i];
      int j = i + 1;
      while (j < steps.length && steps[j].actionLabel == current.actionLabel) {
        j++;
      }

      final count = j - i;
      if (count >= 2) {
        result.add(_GroupedStepGroup(
          actionLabel: current.actionLabel,
          isBatch: true,
          subSteps: steps.sublist(i, j),
        ));
      } else {
        result.add(_GroupedStepGroup(
          actionLabel: current.actionLabel,
          isBatch: false,
          step: current,
        ));
      }
      i = j;
    }
    return result;
  }
}

class _GroupedStepGroup {
  final String actionLabel;
  final bool isBatch;
  final ToolStepModel? step;
  final List<ToolStepModel> subSteps;

  _GroupedStepGroup({
    required this.actionLabel,
    required this.isBatch,
    this.step,
    List<ToolStepModel>? subSteps,
  }) : subSteps = subSteps ?? [];
}

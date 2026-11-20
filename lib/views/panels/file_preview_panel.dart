import 'package:flutter/material.dart';
import '../../theme/agenthub_theme.dart';

/// 单文件内容预览面板（Antigravity 沉浸式代码与文本视图）
class FilePreviewPanel extends StatelessWidget {
  final String filePath;
  final String content;
  final VoidCallback? onClose;

  const FilePreviewPanel({
    super.key,
    required this.filePath,
    required this.content,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lines = content.split('\n');
    final lineNumberColor = isDark ? const Color(0xFF6E7681) : const Color(0xFF8C959F);
    final textNormalColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292E);

    return Container(
      color: isDark ? const Color(0xFF141414) : const Color(0xFFF9F8F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFEEEEEE),
              border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 16, color: AgentHubTheme.primaryRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filePath,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0969DA).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${lines.length} 行',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0969DA),
                    ),
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: AgentHubTheme.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 沉浸式代码浏览视图（支持多行框选与右键复制）
          Expanded(
            child: SelectionArea(
              contextMenuBuilder: (context, selectableRegionState) {
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: selectableRegionState.contextMenuAnchors,
                  buttonItems: selectableRegionState.contextMenuButtonItems,
                );
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(lines.length, (idx) {
                        final lineText = lines[idx];
                        return Container(
                          width: 900,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 行号列（禁用选中）
                              SelectionContainer.disabled(
                                child: SizedBox(
                                  width: 44,
                                  child: Text(
                                    '${idx + 1}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: 'Menlo, Monaco, Courier, monospace',
                                      fontSize: 12,
                                      height: 1.4,
                                      color: lineNumberColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              // 代码文本
                              Expanded(
                                child: Text(
                                  lineText.isEmpty ? ' ' : lineText,
                                  style: TextStyle(
                                    fontFamily: 'Menlo, Monaco, Courier, monospace',
                                    fontSize: 12.5,
                                    height: 1.4,
                                    color: textNormalColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/checkpoint_model.dart';
import '../../theme/agenthub_theme.dart';

/// 代码差异行类型
enum DiffLineType {
  context,
  add,
  delete,
  hunkHeader,
}

/// 代码差异行数据模型
class DiffLine {
  final DiffLineType type;
  final int? oldLineNumber;
  final int? newLineNumber;
  final String text;

  const DiffLine({
    required this.type,
    this.oldLineNumber,
    this.newLineNumber,
    required this.text,
  });
}

/// 单个文件的差异数据模型
class FileDiff {
  final String filePath;
  final String fileType;
  final int additions;
  final int deletions;
  final List<DiffLine> lines;

  const FileDiff({
    required this.filePath,
    required this.fileType,
    required this.additions,
    required this.deletions,
    required this.lines,
  });
}

/// 解析 Unified Diff 文本为结构化模型
class DiffParser {
  static List<FileDiff> parse(String rawDiff) {
    final fileDiffs = <FileDiff>[];
    if (rawDiff.trim().isEmpty) return fileDiffs;

    final rawLines = rawDiff.split('\n');
    String currentPath = '';
    String currentType = 'modify';
    final currentLines = <DiffLine>[];
    int additions = 0;
    int deletions = 0;

    int oldLineCursor = 1;
    int newLineCursor = 1;

    void flushCurrentFile() {
      if (currentPath.isNotEmpty || currentLines.isNotEmpty) {
        fileDiffs.add(FileDiff(
          filePath: currentPath.isEmpty ? '改动文件' : currentPath,
          fileType: currentType,
          additions: additions,
          deletions: deletions,
          lines: List.from(currentLines),
        ));
      }
      currentPath = '';
      currentType = 'modify';
      currentLines.clear();
      additions = 0;
      deletions = 0;
    }

    final hunkRegex = RegExp(r'^@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@');

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];

      // 检测新文件起始
      if (line.startsWith('diff --git')) {
        flushCurrentFile();
        final parts = line.split(' ');
        if (parts.length >= 4) {
          final bPath = parts[3];
          currentPath = bPath.startsWith('b/') ? bPath.substring(2) : bPath;
        }
        continue;
      }

      if (line.startsWith('new file mode')) {
        currentType = 'add';
        continue;
      }
      if (line.startsWith('deleted file mode')) {
        currentType = 'delete';
        continue;
      }
      if (line.startsWith('--- ') || line.startsWith('+++ ')) {
        // 提取文件名备用
        if (currentPath.isEmpty && line.startsWith('+++ b/')) {
          currentPath = line.substring(6).trim();
        }
        continue;
      }

      // 检测区块头 @@ -start,count +start,count @@
      final hunkMatch = hunkRegex.firstMatch(line);
      if (hunkMatch != null) {
        oldLineCursor = int.tryParse(hunkMatch.group(1) ?? '1') ?? 1;
        newLineCursor = int.tryParse(hunkMatch.group(2) ?? '1') ?? 1;
        currentLines.add(DiffLine(
          type: DiffLineType.hunkHeader,
          text: '@@ 第 $newLineCursor 行 @@',
        ));
        continue;
      }

      // 新增行
      if (line.startsWith('+')) {
        additions++;
        currentLines.add(DiffLine(
          type: DiffLineType.add,
          newLineNumber: newLineCursor++,
          text: line.substring(1),
        ));
        continue;
      }

      // 删除行
      if (line.startsWith('-')) {
        deletions++;
        currentLines.add(DiffLine(
          type: DiffLineType.delete,
          oldLineNumber: oldLineCursor++,
          text: line.substring(1),
        ));
        continue;
      }

      // 普通上下文行
      if (line.startsWith(' ')) {
        currentLines.add(DiffLine(
          type: DiffLineType.context,
          oldLineNumber: oldLineCursor++,
          newLineNumber: newLineCursor++,
          text: line.substring(1),
        ));
        continue;
      }

      // 兜底处理无前缀的代码行
      if (line.trim().isNotEmpty) {
        currentLines.add(DiffLine(
          type: DiffLineType.context,
          oldLineNumber: oldLineCursor++,
          newLineNumber: newLineCursor++,
          text: line,
        ));
      }
    }

    flushCurrentFile();
    return fileDiffs;
  }
}

/// 格式化 Diff 对比弹窗
class DiffDialog extends StatefulWidget {
  final CheckpointModel checkpoint;
  final bool isBusy;
  final VoidCallback onRollback;

  const DiffDialog({
    super.key,
    required this.checkpoint,
    required this.isBusy,
    required this.onRollback,
  });

  @override
  State<DiffDialog> createState() => _DiffDialogState();
}

class _DiffDialogState extends State<DiffDialog> {
  late final List<FileDiff> _files;
  int _selectedFileIndex = 0;

  @override
  void initState() {
    super.initState();
    final content = widget.checkpoint.diffContent;
    final summary = widget.checkpoint.diffSummary;
    final rawDiff = (content != null && content.trim().isNotEmpty) ? content : summary;
    _files = DiffParser.parse(rawDiff);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalAdditions = _files.fold<int>(0, (sum, f) => sum + f.additions);
    final totalDeletions = _files.fold<int>(0, (sum, f) => sum + f.deletions);
    final activeFile = _files.isNotEmpty && _selectedFileIndex < _files.length
        ? _files[_selectedFileIndex]
        : null;

    return Dialog(
      backgroundColor: AgentHubTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AgentHubTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 860,
          maxHeight: 640,
          minWidth: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部标题栏与改动汇总统计
              Row(
                children: [
                  Icon(Icons.difference_outlined, size: 18, color: AgentHubTheme.primaryRed),
                  const SizedBox(width: 8),
                  const Text(
                    '代码改动对比',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  // 增删统计徽章
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2EA44F).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+$totalAdditions',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2EA44F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCF222E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-$totalDeletions',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFCF222E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 多文件切换栏
              if (_files.length > 1) ...[
                Container(
                  height: 34,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _files.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final item = _files[index];
                      final isSelected = index == _selectedFileIndex;
                      return InkWell(
                        onTap: () => setState(() => _selectedFileIndex = index),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark ? const Color(0xFF333333) : const Color(0xFFE4E4E4))
                                : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? AgentHubTheme.primaryRed : AgentHubTheme.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.insert_drive_file_outlined, size: 13, color: AgentHubTheme.textSecondary),
                              const SizedBox(width: 6),
                              Text(
                                item.filePath,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? AgentHubTheme.textPrimary : AgentHubTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '+${item.additions} -${item.deletions}',
                                style: TextStyle(fontSize: 10, color: AgentHubTheme.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              // 当前文件头部条
              if (activeFile != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF202226) : const Color(0xFFEDEDED),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    border: Border.all(color: AgentHubTheme.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 14, color: AgentHubTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        activeFile.filePath,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      _buildFileTypeBadge(activeFile.fileType),
                      const Spacer(),
                      Text(
                        '+${activeFile.additions} 行  -${activeFile.deletions} 行',
                        style: TextStyle(fontSize: 11, color: AgentHubTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],

              // 类似 Antigravity 的两列带行号 Diff 代码视图
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141414) : const Color(0xFFF9F9F9),
                    borderRadius: activeFile != null
                        ? const BorderRadius.vertical(bottom: Radius.circular(8))
                        : BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: AgentHubTheme.border),
                      right: BorderSide(color: AgentHubTheme.border),
                      bottom: BorderSide(color: AgentHubTheme.border),
                    ),
                  ),
                  child: activeFile == null || activeFile.lines.isEmpty
                      ? Center(
                          child: Text(
                            '无详细变动文本',
                            style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 12),
                          ),
                        )
                      : _buildDiffEditorView(activeFile.lines, isDark),
                ),
              ),
              const SizedBox(height: 14),

              // 底部操作栏
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!widget.checkpoint.isRolledBack) ...[
                    OutlinedButton.icon(
                      onPressed: widget.isBusy ? null : widget.onRollback,
                      icon: const Icon(Icons.undo, size: 14),
                      label: const Text('回退此改动', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AgentHubTheme.primaryRed,
                        side: BorderSide(color: AgentHubTheme.primaryRed.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgentHubTheme.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('关闭', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建文件类型标签
  Widget _buildFileTypeBadge(String fileType) {
    Color bg;
    Color fg;
    String label;

    if (fileType == 'add') {
      bg = const Color(0xFF2EA44F).withValues(alpha: 0.15);
      fg = const Color(0xFF2EA44F);
      label = '新增';
    } else if (fileType == 'delete') {
      bg = const Color(0xFFCF222E).withValues(alpha: 0.15);
      fg = const Color(0xFFCF222E);
      label = '删除';
    } else {
      bg = Colors.blue.withValues(alpha: 0.15);
      fg = Colors.blue;
      label = '修改';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 构建仿 Antigravity 带行号的双列 Diff 表格视图
  Widget _buildDiffEditorView(List<DiffLine> lines, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map((line) {
            // Hunk 头部行
            if (line.type == DiffLineType.hunkHeader) {
              return Container(
                width: 820,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: isDark ? const Color(0xFF1E2228) : const Color(0xFFEBF1F8),
                child: Text(
                  line.text,
                  style: TextStyle(
                    fontFamily: 'Menlo, Courier, monospace',
                    fontSize: 11,
                    color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }

            // 新增、删除或普通行
            Color? rowBg;
            Color textFg = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF24292E);
            String symbol = ' ';
            Color symbolColor = Colors.transparent;

            if (line.type == DiffLineType.add) {
              rowBg = isDark ? const Color(0x282EA44F) : const Color(0x2428A745);
              textFg = isDark ? const Color(0xFF7EE787) : const Color(0xFF1E7E34);
              symbol = '+';
              symbolColor = textFg;
            } else if (line.type == DiffLineType.delete) {
              rowBg = isDark ? const Color(0x28CF222E) : const Color(0x24DC3545);
              textFg = isDark ? const Color(0xFFF85149) : const Color(0xFFBD2130);
              symbol = '-';
              symbolColor = textFg;
            }

            return Container(
              width: 820,
              color: rowBg ?? Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  // 旧行号
                  SizedBox(
                    width: 44,
                    child: Text(
                      line.oldLineNumber != null ? '${line.oldLineNumber}' : '',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'Menlo, Courier, monospace',
                        fontSize: 11,
                        color: isDark ? const Color(0xFF6E7681) : const Color(0xFF8C959F),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 新行号
                  SizedBox(
                    width: 44,
                    child: Text(
                      line.newLineNumber != null ? '${line.newLineNumber}' : '',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'Menlo, Courier, monospace',
                        fontSize: 11,
                        color: isDark ? const Color(0xFF6E7681) : const Color(0xFF8C959F),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 变动标记符号列 (+ / -)
                  SizedBox(
                    width: 14,
                    child: Text(
                      symbol,
                      style: TextStyle(
                        fontFamily: 'Menlo, Courier, monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: symbolColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 代码文本正文
                  Expanded(
                    child: Text(
                      line.text.isEmpty ? ' ' : line.text,
                      style: TextStyle(
                        fontFamily: 'Menlo, Courier, monospace',
                        fontSize: 12,
                        height: 1.35,
                        color: textFg,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

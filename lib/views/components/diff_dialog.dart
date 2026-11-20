import 'dart:math';
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
  final int skippedCount;

  const DiffLine({
    required this.type,
    this.oldLineNumber,
    this.newLineNumber,
    required this.text,
    this.skippedCount = 0,
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
    bool isFirstHunkOfFile = true;

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
      oldLineCursor = 1;
      newLineCursor = 1;
      isFirstHunkOfFile = true;
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
        if (currentPath.isEmpty && line.startsWith('+++ b/')) {
          currentPath = line.substring(6).trim();
        }
        continue;
      }

      // 检测区块头 @@ -start,count +start,count @@
      final hunkMatch = hunkRegex.firstMatch(line);
      if (hunkMatch != null) {
        final parsedOld = int.tryParse(hunkMatch.group(1) ?? '1') ?? 1;
        final parsedNew = int.tryParse(hunkMatch.group(2) ?? '1') ?? 1;

        int skipped = 0;
        if (isFirstHunkOfFile) {
          skipped = max(0, parsedNew - 1);
          isFirstHunkOfFile = false;
        } else {
          skipped = max(0, parsedNew - newLineCursor);
        }

        oldLineCursor = parsedOld;
        newLineCursor = parsedNew;

        currentLines.add(DiffLine(
          type: DiffLineType.hunkHeader,
          text: line,
          skippedCount: skipped,
        ));
        continue;
      }

      // 新增行：剥除开头的加号
      if (line.startsWith('+')) {
        additions++;
        currentLines.add(DiffLine(
          type: DiffLineType.add,
          newLineNumber: newLineCursor++,
          text: line.length > 1 ? line.substring(1) : '',
        ));
        continue;
      }

      // 删除行：剥除开头的减号
      if (line.startsWith('-')) {
        deletions++;
        currentLines.add(DiffLine(
          type: DiffLineType.delete,
          oldLineNumber: oldLineCursor++,
          text: line.length > 1 ? line.substring(1) : '',
        ));
        continue;
      }

      // 普通上下文行：剥除开头的单空格，保持原生代码缩进
      if (line.startsWith(' ')) {
        currentLines.add(DiffLine(
          type: DiffLineType.context,
          oldLineNumber: oldLineCursor++,
          newLineNumber: newLineCursor++,
          text: line.length > 1 ? line.substring(1) : '',
        ));
        continue;
      }

      // 兜底处理无标记行
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
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 920,
          maxHeight: 680,
          minWidth: 640,
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
                      color: const Color(0xFF2EA44F).withValues(alpha: 0.15),
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
                      color: const Color(0xFFCF222E).withValues(alpha: 0.15),
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
                                ? (isDark ? const Color(0xFF2D333B) : const Color(0xFFE4E4E4))
                                : (isDark ? const Color(0xFF1E2228) : const Color(0xFFF5F5F5)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? AgentHubTheme.primaryRed : Colors.transparent,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161B22) : const Color(0xFFF0F2F5),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
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

              // Antigravity 风格的沉浸式单列 Diff 编辑器视图
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0D1117) : const Color(0xFFFAFBFC),
                    borderRadius: activeFile != null
                        ? const BorderRadius.vertical(bottom: Radius.circular(8))
                        : BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
                      right: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
                      bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
                    ),
                  ),
                  child: activeFile == null || activeFile.lines.isEmpty
                      ? Center(
                          child: Text(
                            '无详细变动文本',
                            style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 12),
                          ),
                        )
                      : _buildAntigravityDiffView(activeFile.lines, isDark),
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

  /// 构建 Antigravity 沉浸式单列 Diff 视图
  Widget _buildAntigravityDiffView(List<DiffLine> lines, bool isDark) {
    final lineNumberColor = isDark ? const Color(0xFF6E7681) : const Color(0xFF8C959F);
    final textNormalColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292E);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map((line) {
            // Hunk 头部：渲染折叠跳过计数小胶囊
            if (line.type == DiffLineType.hunkHeader) {
              final count = line.skippedCount;
              return Container(
                width: 880,
                padding: const EdgeInsets.symmetric(vertical: 4),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF21262D) : const Color(0xFFE1E4E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count > 0 ? '+$count' : '···',
                    style: TextStyle(
                      fontFamily: 'Menlo, Monaco, Courier, monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF8B949E) : const Color(0xFF586069),
                    ),
                  ),
                ),
              );
            }

            final isDelete = line.type == DiffLineType.delete;
            final isAdd = line.type == DiffLineType.add;

            Color? rowBg;
            if (isDelete) {
              rowBg = isDark ? const Color(0xFF5A1E1E) : const Color(0xFFFFDCE0);
            } else if (isAdd) {
              rowBg = isDark ? const Color(0xFF1E4620) : const Color(0xFFDCFFE4);
            }

            // 单列行号：删除行左侧留空，新增行与普通行显示新行号
            final lineNumStr = isDelete
                ? ''
                : (line.newLineNumber != null ? '${line.newLineNumber}' : '');

            return Container(
              width: 880,
              color: rowBg ?? Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 单列行号区域
                  SizedBox(
                    width: 46,
                    child: Text(
                      lineNumStr,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'Menlo, Monaco, Courier, monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: lineNumberColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 代码文本正文：纯净代码，不带 + 或 - 前缀
                  Expanded(
                    child: Text(
                      line.text.isEmpty ? ' ' : line.text,
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
          }).toList(),
        ),
      ),
    );
  }
}

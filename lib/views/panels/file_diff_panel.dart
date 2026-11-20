import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/checkpoint_model.dart';
import '../../models/chat_message_model.dart';
import '../../models/chat_session_model.dart';
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

/// 单个文件的完整差异数据模型
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

/// 行级 LCS 全量比对与 Unified Diff 解析器
class DiffParser {
  /// 计算两个文件行级比对，生成包含全文件上下文的 DiffLine 列表
  static List<DiffLine> computeLineDiff(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;

    // 当文件极大时避免内存爆炸
    if (n > 2500 || m > 2500 || (n * m > 4000000)) {
      return _fastLineDiff(a, b);
    }

    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < m; j++) {
        if (a[i] == b[j]) {
          dp[i + 1][j + 1] = dp[i][j] + 1;
        } else {
          dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
    }

    int i = n;
    int j = m;
    final stack = <DiffLine>[];

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
        stack.add(DiffLine(
          type: DiffLineType.context,
          oldLineNumber: i,
          newLineNumber: j,
          text: a[i - 1],
        ));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        stack.add(DiffLine(
          type: DiffLineType.add,
          oldLineNumber: null,
          newLineNumber: j,
          text: b[j - 1],
        ));
        j--;
      } else if (i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j])) {
        stack.add(DiffLine(
          type: DiffLineType.delete,
          oldLineNumber: i,
          newLineNumber: null,
          text: a[i - 1],
        ));
        i--;
      }
    }

    return stack.reversed.toList();
  }

  /// 快速前后缀比对
  static List<DiffLine> _fastLineDiff(List<String> a, List<String> b) {
    int prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }

    int suffix = 0;
    while (suffix < (a.length - prefix) &&
        suffix < (b.length - prefix) &&
        a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
      suffix++;
    }

    final lines = <DiffLine>[];
    for (int i = 0; i < prefix; i++) {
      lines.add(DiffLine(
        type: DiffLineType.context,
        oldLineNumber: i + 1,
        newLineNumber: i + 1,
        text: a[i],
      ));
    }

    for (int i = prefix; i < a.length - suffix; i++) {
      lines.add(DiffLine(
        type: DiffLineType.delete,
        oldLineNumber: i + 1,
        newLineNumber: null,
        text: a[i],
      ));
    }

    for (int j = prefix; j < b.length - suffix; j++) {
      lines.add(DiffLine(
        type: DiffLineType.add,
        oldLineNumber: null,
        newLineNumber: j + 1,
        text: b[j],
      ));
    }

    final bSuffixStart = b.length - suffix;
    final aSuffixStart = a.length - suffix;
    for (int k = 0; k < suffix; k++) {
      lines.add(DiffLine(
        type: DiffLineType.context,
        oldLineNumber: aSuffixStart + k + 1,
        newLineNumber: bSuffixStart + k + 1,
        text: b[bSuffixStart + k],
      ));
    }

    return lines;
  }

  /// 过滤紧凑改动视图
  static List<DiffLine> filterCompactLines(List<DiffLine> fullLines, {int contextMargin = 5}) {
    if (fullLines.isEmpty) return [];

    final isChanged = List<bool>.filled(fullLines.length, false);
    for (int idx = 0; idx < fullLines.length; idx++) {
      if (fullLines[idx].type == DiffLineType.add || fullLines[idx].type == DiffLineType.delete) {
        final start = max(0, idx - contextMargin);
        final end = min(fullLines.length - 1, idx + contextMargin);
        for (int k = start; k <= end; k++) {
          isChanged[k] = true;
        }
      }
    }

    final result = <DiffLine>[];
    int skippedCount = 0;

    for (int idx = 0; idx < fullLines.length; idx++) {
      if (isChanged[idx]) {
        if (skippedCount > 0) {
          result.add(DiffLine(
            type: DiffLineType.hunkHeader,
            text: '',
            skippedCount: skippedCount,
          ));
          skippedCount = 0;
        }
        result.add(fullLines[idx]);
      } else {
        skippedCount++;
      }
    }

    if (skippedCount > 0) {
      result.add(DiffLine(
        type: DiffLineType.hunkHeader,
        text: '',
        skippedCount: skippedCount,
      ));
    }

    return result;
  }

  /// 兜底解析 Patch
  static List<FileDiff> parseRawPatch(String rawDiff) {
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

      final hunkMatch = hunkRegex.firstMatch(line);
      if (hunkMatch != null) {
        oldLineCursor = int.tryParse(hunkMatch.group(1) ?? '1') ?? 1;
        newLineCursor = int.tryParse(hunkMatch.group(2) ?? '1') ?? 1;
        currentLines.add(DiffLine(
          type: DiffLineType.hunkHeader,
          text: line,
        ));
        continue;
      }

      if (line.startsWith('+')) {
        additions++;
        currentLines.add(DiffLine(
          type: DiffLineType.add,
          newLineNumber: newLineCursor++,
          text: line.length > 1 ? line.substring(1) : '',
        ));
        continue;
      }

      if (line.startsWith('-')) {
        deletions++;
        currentLines.add(DiffLine(
          type: DiffLineType.delete,
          oldLineNumber: oldLineCursor++,
          text: line.length > 1 ? line.substring(1) : '',
        ));
        continue;
      }

      if (line.startsWith(' ')) {
        currentLines.add(DiffLine(
          type: DiffLineType.context,
          oldLineNumber: oldLineCursor++,
          newLineNumber: newLineCursor++,
          text: line.length > 1 ? line.substring(1) : '',
        ));
        continue;
      }

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

/// 右侧三栏架构中的文件修改内容面板（支持长显与空态）
class FileDiffPanel extends StatefulWidget {
  final CheckpointModel? checkpoint;
  final ChatSessionModel? session;
  final ChatMessageModel? message;
  final VoidCallback? onClose;

  const FileDiffPanel({
    super.key,
    this.checkpoint,
    this.session,
    this.message,
    this.onClose,
  });

  @override
  State<FileDiffPanel> createState() => _FileDiffPanelState();
}

class _FileDiffPanelState extends State<FileDiffPanel> {
  List<FileDiff> _files = [];
  bool _isLoading = true;
  final bool _showFullContext = true;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _fileKeys = {};

  @override
  void initState() {
    super.initState();
    _loadFileDiffs();
  }

  @override
  void didUpdateWidget(covariant FileDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checkpoint?.id != widget.checkpoint?.id) {
      _loadFileDiffs();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFileDiffs() async {
    final ckpt = widget.checkpoint;
    if (ckpt == null) {
      if (mounted) {
        setState(() {
          _files = [];
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final workDir = ckpt.workDir;
    final backupDir = ckpt.backupDir;
    final changedFiles = ckpt.changedFiles;

    final result = <FileDiff>[];

    for (final relPath in changedFiles) {
      try {
        final origFile = File(p.join(backupDir, 'originals', relPath));
        final currFile = File(p.join(workDir, relPath));

        final origExists = origFile.existsSync();
        final currExists = currFile.existsSync();

        if (origExists && currExists) {
          final oldContent = origFile.readAsStringSync();
          final newContent = currFile.readAsStringSync();
          final oldLines = oldContent.split('\n');
          final newLines = newContent.split('\n');

          final lines = DiffParser.computeLineDiff(oldLines, newLines);
          int add = 0;
          int del = 0;
          for (final l in lines) {
            if (l.type == DiffLineType.add) add++;
            if (l.type == DiffLineType.delete) del++;
          }

          result.add(FileDiff(
            filePath: relPath,
            fileType: 'modify',
            additions: add,
            deletions: del,
            lines: lines,
          ));
        } else if (!origExists && currExists) {
          final newContent = currFile.readAsStringSync();
          final newLines = newContent.split('\n');
          int lineNo = 1;
          final lines = newLines.map((text) => DiffLine(
            type: DiffLineType.add,
            oldLineNumber: null,
            newLineNumber: lineNo++,
            text: text,
          )).toList();

          result.add(FileDiff(
            filePath: relPath,
            fileType: 'add',
            additions: lines.length,
            deletions: 0,
            lines: lines,
          ));
        } else if (origExists && !currExists) {
          final oldContent = origFile.readAsStringSync();
          final oldLines = oldContent.split('\n');
          int lineNo = 1;
          final lines = oldLines.map((text) => DiffLine(
            type: DiffLineType.delete,
            oldLineNumber: lineNo++,
            newLineNumber: null,
            text: text,
          )).toList();

          result.add(FileDiff(
            filePath: relPath,
            fileType: 'delete',
            additions: 0,
            deletions: lines.length,
            lines: lines,
          ));
        }
      } catch (_) {}
    }

    if (result.isEmpty) {
      final raw = (ckpt.diffContent != null && ckpt.diffContent!.trim().isNotEmpty)
          ? ckpt.diffContent!
          : ckpt.diffSummary;
      result.addAll(DiffParser.parseRawPatch(raw));
    }

    if (mounted) {
      setState(() {
        _files = result;
        _isLoading = false;
      });
    }
  }

  void _scrollToIndex(int index) {
    final key = _fileKeys[index];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ckpt = widget.checkpoint;

    // 当暂无修改时常显整洁的空态面板
    if (ckpt == null) {
      return Container(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFF9F8F5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
                border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_document, size: 16, color: AgentHubTheme.primaryRed),
                  const SizedBox(width: 8),
                  const Text(
                    '文件修改',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (widget.session?.isCodeMode == true && widget.session?.workDir != null) ...[
                    Icon(Icons.folder_outlined, size: 13, color: AgentHubTheme.textTertiary),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        widget.session!.workDir!,
                        style: TextStyle(fontSize: 11, color: AgentHubTheme.textTertiary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.difference_outlined,
                        size: 48,
                        color: isDark ? const Color(0xFF333333) : const Color(0xFFD0D0D0),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '暂无文件修改',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AgentHubTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '在会话中执行修改代码任务后，文件变动与行级 Diff 将实时呈现于此。',
                        style: TextStyle(
                          fontSize: 12,
                          color: AgentHubTheme.textTertiary,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final totalAdditions = _files.fold<int>(0, (sum, f) => sum + f.additions);
    final totalDeletions = _files.fold<int>(0, (sum, f) => sum + f.deletions);

    return Container(
      color: isDark ? const Color(0xFF141414) : const Color(0xFFF9F8F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部控制栏
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
              border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_document, size: 16, color: AgentHubTheme.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  '文件修改',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_files.length} 个文件',
                  style: TextStyle(fontSize: 11, color: AgentHubTheme.textSecondary),
                ),
                const SizedBox(width: 8),
                // 增删统计徽章
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2EA44F).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+$totalAdditions',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF2EA44F),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCF222E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '-$totalDeletions',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFCF222E),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.onClose != null) ...[
                  InkWell(
                    onTap: widget.onClose,
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

          // 多文件快速横向导航条
          if (_files.length > 1) ...[
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: isDark ? const Color(0xFF181818) : const Color(0xFFF2F0EB),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final item = _files[index];
                  return InkWell(
                    onTap: () => _scrollToIndex(index),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF24292E) : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AgentHubTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.insert_drive_file_outlined, size: 11, color: AgentHubTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            item.filePath,
                            style: TextStyle(fontSize: 10, color: AgentHubTheme.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '+${item.additions} -${item.deletions}',
                            style: TextStyle(fontSize: 9, color: AgentHubTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // 主体展示区（支持自适应连续滚动）
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _files.isEmpty
                    ? Center(
                        child: Text(
                          '暂无变动文件内容',
                          style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 12),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final fileDiff = _files[index];
                          final key = _fileKeys.putIfAbsent(index, () => GlobalKey());
                          return _buildFileCard(key, fileDiff, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  /// 构建单个文件的 Diff 卡片
  Widget _buildFileCard(Key key, FileDiff fileDiff, bool isDark) {
    final displayLines = _showFullContext
        ? fileDiff.lines
        : DiffParser.filterCompactLines(fileDiff.lines);

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1117) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件标题条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFFF0F2F5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              border: Border(
                bottom: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 13, color: AgentHubTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  fileDiff.filePath,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                _buildFileTypeBadge(fileDiff.fileType),
                const Spacer(),
                Text(
                  '+${fileDiff.additions} 行  -${fileDiff.deletions} 行',
                  style: TextStyle(fontSize: 10, color: AgentHubTheme.textSecondary),
                ),
              ],
            ),
          ),
          // Antigravity 沉浸式代码比对视图
          _buildAntigravityCodeView(displayLines, isDark),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// Antigravity 风格沉浸式代码比对视图（支持多行框选与右键复制）
  Widget _buildAntigravityCodeView(List<DiffLine> lines, bool isDark) {
    final lineNumberColor = isDark ? const Color(0xFF6E7681) : const Color(0xFF8C959F);
    final textNormalColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF24292E);

    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: selectableRegionState.contextMenuButtonItems,
        );
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines.map((line) {
              // Hunk 折叠胶囊（禁用选择）
              if (line.type == DiffLineType.hunkHeader) {
                final count = line.skippedCount;
                return SelectionContainer.disabled(
                  child: Container(
                    width: 900,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF21262D) : const Color(0xFFE1E4E8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count > 0 ? '+$count more lines' : '···',
                        style: TextStyle(
                          fontFamily: 'Menlo, Monaco, Courier, monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF8B949E) : const Color(0xFF586069),
                        ),
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

              final lineNumStr = isDelete
                  ? ''
                  : (line.newLineNumber != null ? '${line.newLineNumber}' : '');

              return Container(
                width: 900,
                color: rowBg ?? Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 单列行号（禁用选择，防止混入复制代码）
                    SelectionContainer.disabled(
                      child: SizedBox(
                        width: 44,
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
                    ),
                    const SizedBox(width: 14),
                    // 代码文本正文
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
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/checkpoint_model.dart';
import '../utils/path_utils.dart';
import 'database_service.dart';

/// 文件元数据快照
class _FileMeta {
  final int size;
  final int modifiedMs;
  final String content;

  _FileMeta({
    required this.size,
    required this.modifiedMs,
    required this.content,
  });
}

/// 工作区文件快照、差异计算与一键回滚服务
class CheckpointService {
  static final CheckpointService instance = CheckpointService._internal();
  CheckpointService._internal();

  final DatabaseService _db = DatabaseService.instance;

  // 内存中暂存执行前的会话工作区状态: key 为 "${sessionId}_${messageId}"
  final Map<String, Map<String, _FileMeta>> _preStates = {};

  // 需要跳过的目录集合
  static const Set<String> _ignoredDirs = {
    '.git',
    '.svn',
    '.hg',
    'node_modules',
    'build',
    '.dart_tool',
    '.idea',
    '.vscode',
    '.gradle',
    '.agenthub',
    'dist',
    'target',
  };

  /// 任务执行前捕获工作目录文件快照
  Future<void> capturePreState({
    required String sessionId,
    required String messageId,
    required String workDir,
  }) async {
    final key = '${sessionId}_$messageId';
    final dir = Directory(workDir);
    if (!dir.existsSync()) {
      return;
    }

    final fileMap = <String, _FileMeta>{};
    await _scanDirectory(dir, workDir, fileMap);
    _preStates[key] = fileMap;
  }

  /// 递归扫描工作目录并记录文件元数据
  Future<void> _scanDirectory(
    Directory dir,
    String rootPath,
    Map<String, _FileMeta> map,
  ) async {
    try {
      final entries = dir.listSync(followLinks: false);
      for (final entry in entries) {
        final baseName = p.basename(entry.path);
        if (_ignoredDirs.contains(baseName) || baseName.startsWith('.')) {
          continue;
        }

        if (entry is Directory) {
          await _scanDirectory(entry, rootPath, map);
        } else if (entry is File) {
          final stat = entry.statSync();
          // 跳过大于 2MB 的超大文件避免内存暴涨
          if (stat.size > 2 * 1024 * 1024) {
            continue;
          }
          final relPath = p.relative(entry.path, from: rootPath);
          String content = '';
          try {
            content = entry.readAsStringSync();
          } catch (_) {}

          map[relPath] = _FileMeta(
            size: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            content: content,
          );
        }
      }
    } catch (_) {}
  }

  /// 任务执行完成后对比文件差异，生成可回退的 Checkpoint
  Future<CheckpointModel?> finalizeCheckpoint({
    required String sessionId,
    required String messageId,
    required String workDir,
  }) async {
    final key = '${sessionId}_$messageId';
    final preMap = _preStates.remove(key);
    if (preMap == null) {
      return null;
    }

    final postMap = <String, _FileMeta>{};
    final dir = Directory(workDir);
    if (!dir.existsSync()) {
      return null;
    }

    await _scanDirectory(dir, workDir, postMap);

    final changedFiles = <String>[];
    final addedFiles = <String>[];
    final modifiedFiles = <String>[];
    final deletedFiles = <String>[];

    final diffBuffer = StringBuffer();

    // 检查修改和新增
    for (final entry in postMap.entries) {
      final rel = entry.key;
      final post = entry.value;
      if (!preMap.containsKey(rel)) {
        addedFiles.add(rel);
        changedFiles.add(rel);
        diffBuffer.writeln('新增文件: $rel (+${post.content.split('\n').length} 行)');
      } else {
        final pre = preMap[rel]!;
        if (pre.content != post.content) {
          modifiedFiles.add(rel);
          changedFiles.add(rel);
          diffBuffer.writeln('修改文件: $rel');
        }
      }
    }

    // 检查删除
    for (final entry in preMap.entries) {
      final rel = entry.key;
      if (!postMap.containsKey(rel)) {
        deletedFiles.add(rel);
        changedFiles.add(rel);
        diffBuffer.writeln('删除文件: $rel');
      }
    }

    // 没有文件改动则不生成 Checkpoint
    if (changedFiles.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final ckptId = 'ckpt_${now.millisecondsSinceEpoch}';

    // 创建专属增量备份目录: ~/.agenthub/checkpoints/<sessionId>/<ckptId>/
    final backupRootDir = Directory(p.join(PathUtils.agentHubRootDir, 'checkpoints', sessionId, ckptId));
    if (!backupRootDir.existsSync()) {
      backupRootDir.createSync(recursive: true);
    }

    // 将被修改和被删除文件的任务前原始版本写入备份目录
    final originalsDir = Directory(p.join(backupRootDir.path, 'originals'));
    originalsDir.createSync(recursive: true);

    for (final rel in modifiedFiles) {
      final oldContent = preMap[rel]?.content ?? '';
      final backupFile = File(p.join(originalsDir.path, rel));
      backupFile.parent.createSync(recursive: true);
      backupFile.writeAsStringSync(oldContent);
    }

    for (final rel in deletedFiles) {
      final oldContent = preMap[rel]?.content ?? '';
      final backupFile = File(p.join(originalsDir.path, rel));
      backupFile.parent.createSync(recursive: true);
      backupFile.writeAsStringSync(oldContent);
    }

    // 保存本次变更清单元数据
    final manifest = {
      'modified': modifiedFiles,
      'added': addedFiles,
      'deleted': deletedFiles,
    };
    File(p.join(backupRootDir.path, 'manifest.json')).writeAsStringSync(jsonEncode(manifest));

    final summary = '变更 ${changedFiles.length} 个文件 (修改 ${modifiedFiles.length}, 新增 ${addedFiles.length}, 删除 ${deletedFiles.length})';

    final checkpoint = CheckpointModel(
      id: ckptId,
      sessionId: sessionId,
      messageId: messageId,
      workDir: workDir,
      changedFiles: changedFiles,
      diffSummary: summary,
      diffContent: diffBuffer.toString(),
      backupDir: backupRootDir.path,
      createdAt: now,
      isRolledBack: false,
    );

    await _db.saveCheckpoint(checkpoint);
    return checkpoint;
  }

  /// 回滚指定的 Checkpoint，精准恢复工作区文件
  Future<bool> rollback(CheckpointModel checkpoint) async {
    final workDir = checkpoint.workDir;
    final backupDir = checkpoint.backupDir;

    final manifestFile = File(p.join(backupDir, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      return false;
    }

    Map<String, dynamic> manifest = {};
    try {
      manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }

    final modified = (manifest['modified'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final added = (manifest['added'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final deleted = (manifest['deleted'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final originalsDir = Directory(p.join(backupDir, 'originals'));

    // 1. 恢复修改的文件为旧版本
    for (final rel in modified) {
      final orig = File(p.join(originalsDir.path, rel));
      final target = File(p.join(workDir, rel));
      if (orig.existsSync()) {
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(orig.readAsStringSync());
      }
    }

    // 2. 删除任务中新增的文件
    for (final rel in added) {
      final target = File(p.join(workDir, rel));
      if (target.existsSync()) {
        target.deleteSync();
      }
    }

    // 3. 恢复任务中被删除的文件
    for (final rel in deleted) {
      final orig = File(p.join(originalsDir.path, rel));
      final target = File(p.join(workDir, rel));
      if (orig.existsSync()) {
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(orig.readAsStringSync());
      }
    }

    checkpoint.isRolledBack = true;
    await _db.updateCheckpoint(checkpoint);
    return true;
  }
}

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/attachment.dart';

/// 附件管理与暂存服务
class AttachmentService {
  static final AttachmentService instance = AttachmentService._internal();
  AttachmentService._internal();

  static const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
  static const _codeExts = {
    'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'go', 'java',
    'rs', 'c', 'cpp', 'h', 'swift', 'kt', 'rb', 'php',
    'sh', 'sql', 'html', 'css', 'scss', 'vue',
  };

  /// 解析附件文件类型
  AttachmentType resolveType(String filePath) {
    final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
    if (_imageExts.contains(ext)) {
      return AttachmentType.image;
    }
    if (_codeExts.contains(ext)) {
      return AttachmentType.code;
    }
    return AttachmentType.document;
  }

  /// 将文件暂存到实例工作目录下的 .agenthub_assets/
  Future<Attachment> stageFile({
    required String sourcePath,
    required String instanceWorkDir,
  }) async {
    final assetsDir = Directory(p.join(instanceWorkDir, '.agenthub_assets'));
    if (!assetsDir.existsSync()) {
      assetsDir.createSync(recursive: true);
    }

    final sourceFile = File(sourcePath);
    final fileName = p.basename(sourcePath);
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final destPath = p.join(assetsDir.path, uniqueName);

    await sourceFile.copy(destPath);
    final fileSize = await sourceFile.length();

    return Attachment(
      id: uniqueName,
      originalPath: sourcePath,
      stagedPath: destPath,
      fileName: fileName,
      fileSize: fileSize,
      type: resolveType(sourcePath),
    );
  }

  /// 拼接 prompt，将用户输入与附件路径合成为 Claude 命令参数（使用相对当前项目路径）
  String buildPromptWithAttachments({
    required String userText,
    required List<Attachment> attachments,
    String? instanceWorkDir,
  }) {
    if (attachments.isEmpty) {
      return userText;
    }

    final buffer = StringBuffer(userText.trim());
    buffer.writeln();

    final images = attachments.where((a) => a.type == AttachmentType.image).toList();
    final files = attachments.where((a) => a.type != AttachmentType.image).toList();

    String toRelative(String fullPath) {
      if (instanceWorkDir != null && instanceWorkDir.isNotEmpty && fullPath.startsWith(instanceWorkDir)) {
        final rel = p.relative(fullPath, from: instanceWorkDir);
        return './$rel';
      }
      return fullPath;
    }

    if (images.isNotEmpty) {
      buffer.writeln('\n附带图片文件:');
      for (int i = 0; i < images.length; i++) {
        buffer.writeln('- 图片${i + 1}: ${toRelative(images[i].stagedPath)}');
      }
    }

    if (files.isNotEmpty) {
      buffer.writeln('\n附带文本/源码文件:');
      for (int i = 0; i < files.length; i++) {
        buffer.writeln('- 附件${i + 1}: ${toRelative(files[i].stagedPath)}');
      }
    }

    return buffer.toString();
  }

  /// 清空工作目录下的临时附件文件夹
  Future<void> cleanAssets(String instanceWorkDir) async {
    final assetsDir = Directory(p.join(instanceWorkDir, '.agenthub_assets'));
    if (assetsDir.existsSync()) {
      try {
        await assetsDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

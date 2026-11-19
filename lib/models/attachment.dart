/// 附件类型枚举
enum AttachmentType {
  image,    // 图片 (png, jpg, jpeg, gif, webp)
  document, // 文本文档 (txt, md, json, yaml, xml, csv, log)
  code,     // 源码文件 (dart, js, ts, py, go, java 等)
}

/// 附件数据模型
class Attachment {
  final String id;
  final String originalPath;
  final String stagedPath;
  final String fileName;
  final int fileSize;
  final AttachmentType type;

  const Attachment({
    required this.id,
    required this.originalPath,
    required this.stagedPath,
    required this.fileName,
    required this.fileSize,
    required this.type,
  });

  /// 人类可读的文件大小展示
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

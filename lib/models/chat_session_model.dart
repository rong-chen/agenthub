import 'dart:convert';
import 'chat_message_model.dart';

/// 真实用户对话会话模型
class ChatSessionModel {
  final String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessageModel> messages;
  int unreadCount;
  String channel; // internal | wechat
  DateTime? deletedAt;
  String? profileId;
  int tokensUsed;
  String sessionMode; // chat | code
  String? workDir;

  ChatSessionModel({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessageModel>? messages,
    this.unreadCount = 0,
    this.channel = 'internal',
    this.deletedAt,
    this.profileId,
    this.tokensUsed = 0,
    this.sessionMode = 'chat',
    this.workDir,
  }) : messages = messages ?? [];

  /// 是否为代码模式 (绑定 Claude Code 独立实例)
  bool get isCodeMode => sessionMode == 'code';

  /// 计算会话内容真实大小 (字节)
  int get sizeInBytes {
    int bytes = utf8.encode(title).length;
    for (final m in messages) {
      bytes += utf8.encode(m.content).length;
      if (m.toolName != null) bytes += utf8.encode(m.toolName!).length;
      if (m.toolInput != null) bytes += utf8.encode(m.toolInput!).length;
      if (m.toolOutput != null) bytes += utf8.encode(m.toolOutput!).length;
    }
    return bytes;
  }

  /// 格式化会话大小
  String get formattedSize {
    final bytes = sizeInBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// 计算会话用量 (Tokens)
  int get totalTokens {
    if (tokensUsed > 0) return tokensUsed;
    int chars = 0;
    for (final m in messages) {
      chars += m.content.length;
    }
    return (chars / 2.5).round();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'unreadCount': unreadCount,
        'channel': channel,
        'deletedAt': deletedAt?.toIso8601String(),
        'profileId': profileId,
        'tokensUsed': tokensUsed,
        'sessionMode': sessionMode,
        'workDir': workDir,
      };

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List? ?? [];
    return ChatSessionModel(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? '新会话',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      messages: rawMessages
          .map((item) => ChatMessageModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      channel: json['channel']?.toString() ?? 'internal',
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'].toString())
          : null,
      profileId: json['profileId']?.toString(),
      tokensUsed: (json['tokensUsed'] as num?)?.toInt() ?? 0,
      sessionMode: json['sessionMode']?.toString() ?? 'chat',
      workDir: json['workDir']?.toString(),
    );
  }
}

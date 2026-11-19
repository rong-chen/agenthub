import 'checkpoint_model.dart';

/// 消息角色类型
enum MessageRole {
  user,
  assistant,
  system,
  tool,
}

/// 消息发送状态
enum MessageStatus {
  sending,
  streaming,
  done,
  error,
}

/// 聊天消息模型
class ChatMessageModel {
  final String id;
  final MessageRole role;
  String content;
  final DateTime timestamp;
  MessageStatus status;
  String? toolName;
  String? toolInput;
  String? toolOutput;
  List<String>? attachments;
  String? thinking;
  bool isThinking;
  String? checkpointId;
  CheckpointModel? checkpoint;

  ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.done,
    this.toolName,
    this.toolInput,
    this.toolOutput,
    this.attachments,
    this.thinking,
    this.isThinking = false,
    this.checkpointId,
    this.checkpoint,
  });

  /// 转换为 JSON 格式
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'toolName': toolName,
      'toolInput': toolInput,
      'toolOutput': toolOutput,
      'attachments': attachments,
      'thinking': thinking,
      'checkpointId': checkpointId,
    };
  }

  /// 从 JSON 恢复模型
  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => MessageRole.user,
      ),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.done,
      ),
      toolName: json['toolName'] as String?,
      toolInput: json['toolInput'] as String?,
      toolOutput: json['toolOutput'] as String?,
      attachments: (json['attachments'] as List?)?.map((e) => e.toString()).toList(),
      thinking: json['thinking'] as String?,
      checkpointId: json['checkpointId'] as String?,
    );
  }
}

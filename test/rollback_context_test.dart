import 'package:agenthub/models/chat_message_model.dart';
import 'package:agenthub/models/chat_session_model.dart';
import 'package:agenthub/models/checkpoint_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('回滚删除问答轮次消息并提取原始用户指令', () {
    final session = ChatSessionModel(
      id: 'session-1',
      title: '测试会话',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 第一轮历史对话
    final u1 = ChatMessageModel(
      id: 'msg-u1',
      role: MessageRole.user,
      content: '历史指令1',
      timestamp: DateTime.now(),
    );
    final a1 = ChatMessageModel(
      id: 'msg-a1',
      role: MessageRole.assistant,
      content: '历史回复1',
      timestamp: DateTime.now(),
    );

    // 第二轮产生改动的对话
    final u2 = ChatMessageModel(
      id: 'msg-u2',
      role: MessageRole.user,
      content: '请修改 test.txt 文件',
      timestamp: DateTime.now(),
    );
    final a2Tool = ChatMessageModel(
      id: 'msg-a2-tool',
      role: MessageRole.assistant,
      content: '',
      toolName: 'write_file',
      timestamp: DateTime.now(),
    );
    final a2Done = ChatMessageModel(
      id: 'msg-a2-done',
      role: MessageRole.assistant,
      content: '已创建 test.txt 并写入内容',
      checkpointId: 'ckpt-1',
      timestamp: DateTime.now(),
    );

    final ckpt = CheckpointModel(
      id: 'ckpt-1',
      sessionId: 'session-1',
      messageId: 'msg-a2-done',
      workDir: '/tmp',
      changedFiles: ['test.txt'],
      diffSummary: '变更 1 个文件',
      diffContent: 'diff ...',
      backupDir: '/tmp/backup',
      createdAt: DateTime.now(),
      isRolledBack: false,
    );
    a2Done.checkpoint = ckpt;

    session.messages.addAll([u1, a1, u2, a2Tool, a2Done]);

    // 模拟回退算法
    int assistantIndex = session.messages.indexWhere(
      (m) => m.checkpointId == ckpt.id || m.id == ckpt.messageId,
    );
    expect(assistantIndex, 4);

    int userIndex = -1;
    for (int i = assistantIndex - 1; i >= 0; i--) {
      if (session.messages[i].role == MessageRole.user) {
        userIndex = i;
        break;
      }
    }
    expect(userIndex, 2);

    final msgsToDelete = <ChatMessageModel>[];
    String? revertedPrompt;
    if (userIndex != -1) {
      revertedPrompt = session.messages[userIndex].content;
      for (int i = userIndex; i <= assistantIndex; i++) {
        msgsToDelete.add(session.messages[i]);
      }
    }

    expect(revertedPrompt, '请修改 test.txt 文件');
    expect(msgsToDelete.length, 3);
    expect(msgsToDelete.map((m) => m.id).toList(), ['msg-u2', 'msg-a2-tool', 'msg-a2-done']);

    final idsToDelete = msgsToDelete.map((e) => e.id).toSet();
    session.messages.removeWhere((item) => idsToDelete.contains(item.id));

    // 验证会话中只剩下第一轮对话
    expect(session.messages.length, 2);
    expect(session.messages[0].id, 'msg-u1');
    expect(session.messages[1].id, 'msg-a1');
  });
}

import 'package:agenthub/models/chat_message_model.dart';
import 'package:agenthub/models/claude_stream_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatMessageModel 支持多阶段独立思考且序列化反序列化不覆盖', () {
    final msg = ChatMessageModel(
      id: 'msg-1',
      role: MessageRole.assistant,
      content: '任务结果',
      timestamp: DateTime.now(),
      thinkings: [
        '第一阶段思考：先查看项目文件结构',
        '第二阶段思考：发现缺少配置文件，尝试从模版创建',
        '第三阶段思考：创建完成，执行编译验证',
      ],
    );

    expect(msg.thinkings.length, 3);
    expect(msg.thinkings[0], contains('第一阶段思考'));
    expect(msg.thinkings[1], contains('第二阶段思考'));
    expect(msg.thinkings[2], contains('第三阶段思考'));

    final json = msg.toJson();
    final restored = ChatMessageModel.fromJson(json);

    expect(restored.thinkings.length, 3);
    expect(restored.thinkings[0], contains('第一阶段思考'));
    expect(restored.thinkings[1], contains('第二阶段思考'));
    expect(restored.thinkings[2], contains('第三阶段思考'));
  });

  test('ClaudeStreamEvent 解析多思考块且完整保留', () {
    final rawJson = {
      'type': 'assistant',
      'message': {
        'content': [
          {'type': 'thinking', 'thinking': '阶段一思考内容'},
          {'type': 'tool_use', 'name': 'Bash', 'input': {'command': 'ls'}},
          {'type': 'thinking', 'thinking': '阶段二思考内容'},
        ],
      },
    };

    final event = ClaudeStreamEvent.fromJson(rawJson);
    expect(event.thinkings.length, 2);
    expect(event.thinkings[0], '阶段一思考内容');
    expect(event.thinkings[1], '阶段二思考内容');
  });
}

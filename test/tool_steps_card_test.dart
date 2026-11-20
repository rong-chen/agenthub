import 'package:agenthub/models/tool_step_model.dart';
import 'package:agenthub/providers/app_state_provider.dart';
import 'package:agenthub/views/components/tool_steps_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('智能提炼命令与文件操作元数据', () {
    final metaCmd = ToolStepModel.parseToolMeta('Bash', '{"command": "ls -la"}');
    expect(metaCmd.actionLabel, '运行命令');
    expect(metaCmd.target, 'ls -la');

    final metaRead = ToolStepModel.parseToolMeta('ReadFile', '{"file_path": "README.md"}');
    expect(metaRead.actionLabel, '读取文件');
    expect(metaRead.target, './README.md');

    final metaEdit = ToolStepModel.parseToolMeta('EditFile', '{"file_path": "lib/main.dart"}');
    expect(metaEdit.actionLabel, '编辑文件');
    expect(metaEdit.target, './lib/main.dart');
  });

  testWidgets('ToolStepsCard 渲染单步骤与批量卡片测试', (tester) async {
    final steps = [
      ToolStepModel.fromRaw(
        toolName: 'Bash',
        input: '{"command": "ls"}',
        status: ToolStepStatus.success,
      ),
      ToolStepModel.fromRaw(
        toolName: 'ReadFile',
        input: '{"file_path": "README.md"}',
        status: ToolStepStatus.success,
      ),
      // 两个连续的 Bash 步骤应自动聚合成“批量运行命令 (2)”
      ToolStepModel.fromRaw(
        toolName: 'Bash',
        input: '{"command": "find ."}',
        status: ToolStepStatus.success,
      ),
      ToolStepModel.fromRaw(
        toolName: 'Bash',
        input: '{"command": "cat config.json"}',
        status: ToolStepStatus.error,
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<AppStateProvider>(
        create: (_) => AppStateProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: ToolStepsCard(steps: steps),
          ),
        ),
      ),
    );

    // 验证渲染出“运行命令”、“读取文件”与批量标题
    expect(find.text('运行命令'), findsOneWidget);
    expect(find.text('读取文件'), findsOneWidget);
    expect(find.text('./README.md'), findsOneWidget);
    expect(find.text('批量运行命令 (2)'), findsOneWidget);
    expect(find.text('1 失败'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/models/tool_step_model.dart';
import 'package:agenthub/views/components/tool_steps_card.dart';

void main() {
  testWidgets('ToolStepsCard renders stop button for running long task', (WidgetTester tester) async {
    final stepRunning = ToolStepModel(
      id: 'step_running',
      toolName: 'Bash',
      actionLabel: '运行命令',
      target: 'npm i',
      status: ToolStepStatus.running,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolStepsCard(steps: [stepRunning]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 应该显示“停止任务”按钮
    expect(find.text('停止任务'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
  });

  testWidgets('ToolStepsCard batch card renders stop button when in progress', (WidgetTester tester) async {
    final batchStep1 = ToolStepModel(
      id: 'step_1',
      toolName: 'Bash',
      actionLabel: '运行命令',
      target: 'npm run dev',
      status: ToolStepStatus.running,
    );
    final batchStep2 = ToolStepModel(
      id: 'step_2',
      toolName: 'Bash',
      actionLabel: '运行命令',
      target: 'curl localhost:5173',
      status: ToolStepStatus.running,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolStepsCard(steps: [batchStep1, batchStep2]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 批量卡片标题
    expect(find.text('批量运行命令 (2)'), findsOneWidget);
    // 应该显示“停止任务”按钮
    expect(find.text('停止任务'), findsOneWidget);
  });
}

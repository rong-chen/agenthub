import 'dart:io';
import 'package:agenthub/services/project_service_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ProjectServiceManager 实例创建与日志记录测试', () {
    final manager = ProjectServiceManager.instance;
    final inst = manager.getOrCreateInstance('sess_test_1', '/dummy/path');

    expect(inst.sessionId, 'sess_test_1');
    expect(inst.status, ServiceStatus.stopped);

    inst.appendLog('测试常规日志');
    inst.appendLog('测试错误日志', isError: true);

    expect(inst.logs.length, 2);
    expect(inst.logs[0].text, '测试常规日志');
    expect(inst.logs[0].isError, false);
    expect(inst.logs[1].text, '测试错误日志');
    expect(inst.logs[1].isError, true);

    manager.clearLogs('sess_test_1');
    expect(inst.logs.isEmpty, true);
  });

  test('ProjectServiceManager 默认命令探测', () {
    final manager = ProjectServiceManager.instance;

    // 当前项目应探测为 flutter run（包含 pubspec.yaml）
    final currentDir = Directory.current.path;
    final cmd = manager.detectDefaultCommand(currentDir);
    expect(cmd, 'flutter run');
  });
}

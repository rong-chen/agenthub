import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agenthub/config/app_env.dart';
import 'package:agenthub/services/single_instance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppEnv Environment Tests', () {
    test('AppEnv dev and prod configurations are isolated', () {
      AppEnv.setEnvironment(AppEnvironment.prod);
      expect(AppEnv.isProd, isTrue);
      expect(AppEnv.isDev, isFalse);
      expect(AppEnv.appTitle, 'AgentHub');
      expect(AppEnv.dbFileName, 'agenthub.db');
      expect(AppEnv.defaultGatewayPort, 18789);
      expect(AppEnv.singleInstancePort, 39281);

      AppEnv.setEnvironment(AppEnvironment.dev);
      expect(AppEnv.isDev, isTrue);
      expect(AppEnv.isProd, isFalse);
      expect(AppEnv.appTitle, 'AgentHub (Dev)');
      expect(AppEnv.dbFileName, 'agenthub_dev.db');
      expect(AppEnv.defaultGatewayPort, 18790);
      expect(AppEnv.singleInstancePort, 39282);

      // 恢复生产
      AppEnv.setEnvironment(AppEnvironment.prod);
    });
  });

  group('SingleInstanceService Tests', () {
    test('Primary instance binds successfully and secondary wakes up primary', () async {
      final service = SingleInstanceService.instance;
      const testPort = 39299;

      // 第一次启动
      final isPrimary = await service.ensureSingleInstance(port: testPort);
      expect(isPrimary, isTrue);

      // 模拟第二个进程连接发送 WAKEUP 消息
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, testPort);
      socket.write('WAKEUP\n');
      await socket.flush();
      await socket.close();

      // 释放服务
      await service.dispose();
    });
  });
}

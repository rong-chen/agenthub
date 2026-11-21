import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端单实例应用管理服务
/// 通过本地回环端口监听实现互斥锁与跨进程唤醒
class SingleInstanceService {
  static final SingleInstanceService instance = SingleInstanceService._internal();
  SingleInstanceService._internal();

  ServerSocket? _serverSocket;

  /// 确保当前进程为单实例运行
  /// 若已存在运行中的实例，则唤醒旧实例并退出当前进程
  Future<bool> ensureSingleInstance({required int port}) async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return true;
    }

    try {
      // 尝试绑定本地回环端口
      _serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );

      // 绑定成功，当前为首个实例，监听来自后续启动实例的唤醒请求
      _serverSocket!.listen((Socket client) {
        client.cast<List<int>>().transform(utf8.decoder).listen((message) async {
          if (message.trim() == 'WAKEUP') {
            await wakeupWindow();
          }
        });
      });

      return true;
    } catch (_) {
      // 端口被占用，说明已有实例在运行
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(seconds: 1),
        );
        socket.write('WAKEUP\n');
        await socket.flush();
        await socket.close();
      } catch (_) {}

      // 退出当前重复启动的进程
      exit(0);
    }
  }

  /// 唤醒并置顶当前桌面窗口
  Future<void> wakeupWindow() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('唤醒窗口失败: $e');
    }
  }

  /// 关闭释放单实例端口
  Future<void> dispose() async {
    await _serverSocket?.close();
    _serverSocket = null;
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/app_state_provider.dart';
import 'services/tray_service.dart';
import 'theme/agenthub_theme.dart';
import 'views/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端初始化 SQLite FFI
  sqfliteFfiInit();

  // 桌面端窗口配置
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();

      const WindowOptions windowOptions = WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(960, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        title: 'AgentHub',
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setPreventClose(true);
        await windowManager.center();
        await windowManager.show();
        await windowManager.focus();
      });

      // 初始化系统托盘
      await TrayService.instance.initTray();
    } catch (_) {}
  }

  // 预先从 SQLite 加载全局配置（确保第一帧即采用用户保存的明暗主题）
  final appState = AppStateProvider();
  await appState.initialize();

  // 启动应用根组件
  runApp(AgentHubApp(provider: appState));
}

/// 应用程序根组件
class AgentHubApp extends StatelessWidget {
  final AppStateProvider? provider;
  const AgentHubApp({super.key, this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider != null) {
      return ChangeNotifierProvider.value(
        value: provider!,
        child: const _AgentHubAppBody(),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => AppStateProvider()..initialize(),
      child: const _AgentHubAppBody(),
    );
  }
}

class _AgentHubAppBody extends StatelessWidget {
  const _AgentHubAppBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final isDark = provider.isDarkTheme;
    // 同步全局主题模式
    AgentHubTheme.isDark = isDark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AgentHubTheme.buildTheme(false),
      darkTheme: AgentHubTheme.buildTheme(true),
      home: const HomeView(),
    );
  }
}

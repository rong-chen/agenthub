import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'config/app_env.dart';
import 'providers/app_state_provider.dart';
import 'services/single_instance_service.dart';
import 'services/tray_service.dart';
import 'theme/agenthub_theme.dart';
import 'views/home_view.dart';

/// 应用程序通用启动逻辑
Future<void> startApp({AppEnvironment? environment}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 若显式传入了环境，则更新全局环境配置
  if (environment != null) {
    AppEnv.setEnvironment(environment);
  }

  // 桌面端单实例互斥校验：只允许打开一个应用，重复打开自动唤醒已有实例并退出新实例
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final isPrimary = await SingleInstanceService.instance.ensureSingleInstance(
      port: AppEnv.singleInstancePort,
    );
    if (!isPrimary) {
      return;
    }
  }

  // 桌面端初始化 SQLite FFI
  sqfliteFfiInit();

  // 桌面端窗口配置
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();

      final WindowOptions windowOptions = WindowOptions(
        size: const Size(1440, 900),
        minimumSize: const Size(960, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        title: AppEnv.appTitle,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setPreventClose(true);
        // 打开应用，铺满屏幕全屏（宽度和高度全屏最大化）
        await windowManager.maximize();
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

/// 默认主入口（支持通过 --dart-define=ENV=dev 动态指定，缺省为生产环境）
void main() async {
  await startApp();
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
      debugShowCheckedModeBanner: AppEnv.isDev,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AgentHubTheme.buildTheme(false),
      darkTheme: AgentHubTheme.buildTheme(true),
      home: const HomeView(),
    );
  }
}

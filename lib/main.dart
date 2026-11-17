import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/app_state_provider.dart';
import 'services/tray_service.dart';
import 'theme/openclaw_theme.dart';
import 'views/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端初始化 SQLite FFI
  sqfliteFfiInit();

  // 桌面端窗口配置
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();

      // 初始化系统托盘
      await TrayService.instance.initTray();
    } catch (_) {}
  }

  // 启动应用根组件
  runApp(const OpenClawApp());
}

/// 应用程序根组件
class OpenClawApp extends StatelessWidget {
  const OpenClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppStateProvider()..initialize(),
      child: Consumer<AppStateProvider>(
        builder: (context, provider, _) {
          final isDark = provider.isDarkTheme;
          // 同步全局主题模式
          OpenClawTheme.isDark = isDark;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            theme: OpenClawTheme.buildTheme(false),
            darkTheme: OpenClawTheme.buildTheme(true),
            home: const HomeView(),
          );
        },
      ),
    );
  }
}

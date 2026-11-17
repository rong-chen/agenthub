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

  // 初始化桌面窗口管理
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const WindowOptions windowOptions = WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'AgentHub',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.maximize();
      await windowManager.focus();
    });

    // 初始化系统托盘
    await TrayService.instance.initTray();
  }

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
          return MaterialApp(
            title: 'AgentHub',
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

import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘服务，负责处理任务栏托盘图标与窗口切换
class TrayService with TrayListener {
  static final TrayService instance = TrayService._internal();
  TrayService._internal();

  /// 初始化托盘图标与右键菜单
  Future<void> initTray() async {
    trayManager.addListener(this);

    final iconPath = Platform.isWindows
        ? 'assets/icons/app_icon.png'
        : 'assets/icons/tray_icon.png';

    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('服务运行中');
    await updateContextMenu();
  }

  /// 更新托盘菜单项
  Future<void> updateContextMenu({
    int activeSkillsCount = 0,
    bool isGatewayConnected = false,
    int port = 18789,
  }) async {
    final statusText = isGatewayConnected
        ? '本地网关在线: 端口 $port'
        : '本地网关未启动';
    final skillsText = '本地技能: $activeSkillsCount 项';

    final Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: '显示主界面',
        ),
        MenuItem(
          key: 'hide_window',
          label: '隐藏到托盘',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'gateway_status',
          label: statusText,
          disabled: true,
        ),
        MenuItem(
          key: 'skills_count',
          label: skillsText,
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: '退出应用',
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  DateTime _lastClickTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onTrayIconMouseDown() {
    final now = DateTime.now();
    if (now.difference(_lastClickTime).inMilliseconds < 250) {
      return;
    }
    _lastClickTime = now;
    _toggleWindowVisibility();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      _showWindow();
      return;
    }

    if (menuItem.key == 'hide_window') {
      windowManager.hide();
      return;
    }

    if (menuItem.key == 'exit_app') {
      windowManager.destroy();
      exit(0);
    }
  }

  /// 切换主窗口显隐状态
  Future<void> _toggleWindowVisibility() async {
    final isVisible = await windowManager.isVisible();
    final isFocused = await windowManager.isFocused();
    final isMinimized = await windowManager.isMinimized();

    if (isMinimized) {
      await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
      return;
    }

    // 只有窗口处于显示状态且当前正是前台聚焦窗口时，点击才收起隐藏
    if (isVisible && isFocused) {
      await windowManager.hide();
      return;
    }

    // 若窗口未显示，或窗口在后台（被其他软件遮挡/失去焦点），点击直接拉至最前台并聚焦
    await _showWindow();
  }

  /// 显示并聚焦窗口
  Future<void> _showWindow() async {
    final isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// 销毁资源
  void dispose() {
    trayManager.removeListener(this);
  }
}

import 'package:flutter/material.dart';

/// OpenClaw 风格全局配色与视觉主题规范（支持暖纸明亮与 VS Code 暗黑双主题）
class OpenClawTheme {
  // 当前主题模式标识
  static bool isDark = false;

  // 基础背景
  static Color get background => isDark ? const Color(0xFF181818) : const Color(0xFFF9F8F5);
  static Color get sidebarBackground => isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F0EB);
  static Color get cardBackground => isDark ? const Color(0xFF252526) : Colors.white;
  static Color get headerBackground => isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9F8F5);

  // 品牌色调（赤陶红 / 砖红）
  static const Color primaryRed = Color(0xFFBA3824);
  static const Color primaryRedHover = Color(0xFFA5301E);
  static Color get primaryRedLight => isDark ? const Color(0xFF3B2320) : const Color(0xFFFCEEE9);
  static Color get titleRed => isDark ? const Color(0xFFE2614E) : const Color(0xFF942B18);

  // 辅助状态色
  static const Color statusGreen = Color(0xFF10B981);
  static const Color statusOrange = Color(0xFFF59E0B);
  static const Color statusGray = Color(0xFF9CA3AF);

  // 文本色阶
  static Color get textPrimary => isDark ? const Color(0xFFCCCCCC) : const Color(0xFF22201D);
  static Color get textSecondary => isDark ? const Color(0xFF969696) : const Color(0xFF6B6762);
  static Color get textTertiary => isDark ? const Color(0xFF6E6E6E) : const Color(0xFF9E9A93);

  // 边框与分割线
  static Color get border => isDark ? const Color(0xFF333333) : const Color(0xFFE8E5DD);
  static Color get divider => isDark ? const Color(0xFF282828) : const Color(0xFFEFECE6);
  static Color get inputBackground => isDark ? const Color(0xFF2A2A2A) : Colors.white;
  static Color get pillBackground => isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEAE7E0);

  /// 构建全局 ThemeData
  static ThemeData buildTheme(bool dark) {
    isDark = dark;
    return ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: primaryRed,
      colorScheme: dark
          ? const ColorScheme.dark(
              primary: primaryRed,
              surface: Color(0xFF252526),
              onSurface: Color(0xFFCCCCCC),
            )
          : const ColorScheme.light(
              primary: primaryRed,
              surface: Colors.white,
              onSurface: Color(0xFF22201D),
            ),
      dividerColor: divider,
      fontFamily: 'PingFang SC',
    );
  }
}

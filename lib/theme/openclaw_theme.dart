import 'dart:io';
import 'package:flutter/material.dart';

/// 全局配色与视觉主题规范（暖纸明亮 / VS Code 暗黑双主题）
class OpenClawTheme {
  // 当前主题模式标识
  static bool isDark = false;

  // 基础背景
  static Color get background => isDark ? const Color(0xFF181818) : const Color(0xFFF9F8F5);
  static Color get sidebarBackground => isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F0EB);
  static Color get cardBackground => isDark ? const Color(0xFF252526) : Colors.white;
  // 顶栏与内容区同色，视觉统一
  static Color get headerBackground => background;

  // 品牌色调
  static const Color primaryRed = Color(0xFFBA3824);
  static const Color primaryRedHover = Color(0xFFA5301E);
  static Color get primaryRedLight => isDark ? const Color(0xFF3B2320) : const Color(0xFFFCEEE9);
  static Color get titleRed => isDark ? const Color(0xFFE2614E) : const Color(0xFF942B18);

  // 辅助状态色
  static const Color statusGreen = Color(0xFF10B981);
  static const Color statusOrange = Color(0xFFF59E0B);
  static const Color statusGray = Color(0xFF9CA3AF);

  // 文本色阶（提高清晰度与对比度，防止字体过虚）
  static Color get textPrimary => isDark ? const Color(0xFFF3F3F3) : const Color(0xFF1C1A18);
  static Color get textSecondary => isDark ? const Color(0xFFA6A6A6) : const Color(0xFF4A4744);
  static Color get textTertiary => isDark ? const Color(0xFF808080) : const Color(0xFF787570);

  // 边框与分割线
  static Color get border => isDark ? const Color(0xFF333333) : const Color(0xFFE8E5DD);
  static Color get divider => isDark ? const Color(0xFF282828) : const Color(0xFFEFECE6);
  static Color get inputBackground => isDark ? const Color(0xFF2A2A2A) : Colors.white;
  static Color get pillBackground => isDark ? const Color(0xFF2D2D2D) : const Color(0xFFEAE7E0);

  /// 构建全局 ThemeData
  static ThemeData buildTheme(bool dark) {
    final bg = dark ? const Color(0xFF181818) : const Color(0xFFF9F8F5);
    final cardBg = dark ? const Color(0xFF252526) : Colors.white;
    final txtPrimary = dark ? const Color(0xFFF3F3F3) : const Color(0xFF1C1A18);
    final txtSecondary = dark ? const Color(0xFFA6A6A6) : const Color(0xFF4A4744);
    final txtTertiary = dark ? const Color(0xFF808080) : const Color(0xFF787570);
    final bdr = dark ? const Color(0xFF333333) : const Color(0xFFE8E5DD);
    final div = dark ? const Color(0xFF282828) : const Color(0xFFEFECE6);

    final colorScheme = dark
        ? const ColorScheme.dark(
            primary: primaryRed,
            surface: Color(0xFF252526),
            onSurface: Color(0xFFF3F3F3),
          )
        : const ColorScheme.light(
            primary: primaryRed,
            surface: Colors.white,
            onSurface: Color(0xFF1C1A18),
          );

    return ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      primaryColor: primaryRed,
      colorScheme: colorScheme,
      dividerColor: div,
      fontFamily: Platform.isWindows ? 'Microsoft YaHei UI' : 'PingFang SC',
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'PingFang SC',
        'Segoe UI',
        'Hiragino Sans GB',
        'sans-serif',
      ],
      // 全局文本字重优化，加粗防虚化
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: txtPrimary, fontWeight: FontWeight.w500, fontSize: 14),
        bodyMedium: TextStyle(color: txtPrimary, fontWeight: FontWeight.w500, fontSize: 13),
        bodySmall: TextStyle(color: txtSecondary, fontWeight: FontWeight.w500, fontSize: 12),
        titleMedium: TextStyle(color: txtPrimary, fontWeight: FontWeight.w600, fontSize: 15),
        titleLarge: TextStyle(color: txtPrimary, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      // 顶栏主题：与背景一致
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: txtPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      // 输入框提示词主题
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: txtTertiary, fontSize: 13),
      ),
      // 卡片主题
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: bdr),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// 全局增强型文本控制器
/// 解决 Flutter 桌面端（尤其 macOS）光标与末尾文字紧贴黏连、缺乏呼吸感的问题
class AppTextEditingController extends TextEditingController {
  AppTextEditingController({super.text, this.caretSpacing = 2.5});

  /// 光标与末尾字符之间的呼吸间隙（物理像素，推荐 2.0 ~ 3.0）
  final double caretSpacing;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // 若正在处于输入法拼音/合成选词状态，遵循系统底层高亮排版
    final bool hasComposing = withComposing && value.isComposingRangeValid;
    if (hasComposing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final effectiveStyle = style ?? const TextStyle();
    final baseLetterSpacing = effectiveStyle.letterSpacing ?? 0.6;
    final normalizedStyle = effectiveStyle.copyWith(letterSpacing: baseLetterSpacing);

    // 单字符时，直接增加字间距以撑开末尾光标
    if (text.length == 1) {
      return TextSpan(
        text: text,
        style: effectiveStyle.copyWith(
          letterSpacing: baseLetterSpacing + caretSpacing,
        ),
      );
    }

    // 多字符时，前 n-1 个字符保持基准字距，末尾字符增加 caretSpacing，将末尾光标自然向右推开
    return TextSpan(
      style: normalizedStyle,
      children: [
        TextSpan(text: text.substring(0, text.length - 1)),
        TextSpan(
          text: text.substring(text.length - 1),
          style: effectiveStyle.copyWith(
            letterSpacing: baseLetterSpacing + caretSpacing,
          ),
        ),
      ],
    );
  }
}

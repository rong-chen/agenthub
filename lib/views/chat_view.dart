import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/chat_message_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/openclaw_theme.dart';

/// 对话交互视图
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  int _lastMessageCount = 0;
  String? _lastSessionId;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// 发送消息处理
  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final provider = context.read<AppStateProvider>();
    if (provider.isBusy) {
      return;
    }
    provider.sendMessage(text);
    _inputController.clear();
    _scrollToBottom();
  }

  /// 平滑动画滚动到最新消息位置
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if ((_scrollController.offset - target).abs() > 1.0) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    OpenClawTheme.isDark = provider.isDarkTheme;
    final messages = provider.messages;

    // 会话切换或新消息到达时平滑滚动到底部
    if (provider.activeSessionId != _lastSessionId) {
      _lastSessionId = provider.activeSessionId;
      _lastMessageCount = messages.length;
      _scrollToBottom();
    } else if (messages.length > _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    } else if (messages.length < _lastMessageCount) {
      _lastMessageCount = messages.length;
    }

    return Container(
      color: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      child: Column(
        children: [
          // 移除了 _buildHeaderRow，直接显示消息区域
          Expanded(
            child: messages.isEmpty
                ? const SizedBox.shrink() // 空状态不显示任何提示
                : _buildMessageList(messages),
          ),
          _buildInputArea(provider),
        ],
      ),
    );
  }

  /// 消息列表
  Widget _buildMessageList(List<ChatMessageModel> messages) {
    // 获取屏幕宽度用于限制气泡宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.7;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isUser = message.role == MessageRole.user;

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                // AI 头像：使用 Icons 替代文本 'A'
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: OpenClawTheme.pillBackground, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Icon(Icons.smart_toy_outlined, size: 18, color: OpenClawTheme.textPrimary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? OpenClawTheme.primaryRedLight : OpenClawTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OpenClawTheme.border),
                    ),
                    child: isUser
                        ? Text(message.content, style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500))
                        : MarkdownBody(
                            data: message.content,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14, height: 1.6, fontWeight: FontWeight.w500),
                              code: TextStyle(backgroundColor: OpenClawTheme.pillBackground, color: OpenClawTheme.titleRed, fontSize: 12, fontWeight: FontWeight.w600),
                              codeblockDecoration: BoxDecoration(
                                color: OpenClawTheme.pillBackground,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: OpenClawTheme.border),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                // 用户头像：使用 Icons 替代文本 'U'
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: OpenClawTheme.primaryRed, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.person_outlined, size: 18, color: Colors.white),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 底部输入区（支持 Enter 发送，Shift+Enter 换行）
  Widget _buildInputArea(AppStateProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: OpenClawTheme.background,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: OpenClawTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OpenClawTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  // Enter 发送消息，Shift+Enter 换行
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _handleSend();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  enabled: !provider.isBusy,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: '输入内容...',
                    hintStyle: TextStyle(color: OpenClawTheme.textTertiary, fontSize: 13),
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (provider.isBusy) ...[
              OutlinedButton(
                onPressed: () => provider.abortCurrentGeneration(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OpenClawTheme.primaryRed,
                  side: const BorderSide(color: OpenClawTheme.primaryRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('停止', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton(
              onPressed: provider.isBusy ? null : _handleSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: OpenClawTheme.primaryRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(provider.isBusy ? '处理中' : '发送', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

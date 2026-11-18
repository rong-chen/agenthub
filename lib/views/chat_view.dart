import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../providers/app_state_provider.dart';
import '../theme/agenthub_theme.dart';

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
  String? _copiedMessageId;
  String? _lastSessionId;
  int _lastMessageCount = 0;

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
    _scrollToBottom(animate: true);
  }

  /// 滚动到消息底部
  void _scrollToBottom({bool animate = true}) {
    void execute() {
      if (!_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (target <= 0) {
        return;
      }
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      execute();
      // 在首帧排版完全计算完各气泡高度后，连续多阶段校准到底部
      Future.delayed(const Duration(milliseconds: 30), execute);
      Future.delayed(const Duration(milliseconds: 80), execute);
      Future.delayed(const Duration(milliseconds: 160), execute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    AgentHubTheme.isDark = provider.isDarkTheme;
    final messages = provider.messages;

    if (_lastSessionId != provider.activeSessionId) {
      _lastSessionId = provider.activeSessionId;
      _lastMessageCount = messages.length;
      _scrollToBottom(animate: false);
    } else if (messages.length != _lastMessageCount || provider.isBusy) {
      _lastMessageCount = messages.length;
      _scrollToBottom(animate: true);
    }

    return Container(
      color: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      child: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const SizedBox.shrink()
                : _buildMessageList(provider, messages),
          ),
          _buildInputArea(provider),
        ],
      ),
    );
  }

  /// 消息列表（从顶部按时间顺序正常向下排列）
  Widget _buildMessageList(AppStateProvider provider, List<ChatMessageModel> messages) {
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                // AI 头像：使用 Icons 替代文本 'A'
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AgentHubTheme.pillBackground, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Icon(Icons.smart_toy_outlined, size: 18, color: AgentHubTheme.textPrimary),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Column(
                    crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUser ? AgentHubTheme.primaryRedLight : AgentHubTheme.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: message.status == MessageStatus.error ? AgentHubTheme.primaryRed : AgentHubTheme.border),
                        ),
                        child: isUser
                            ? Text(
                                message.content,
                                style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
                              )
                            : MarkdownBody(
                                selectable: false,
                                data: message.content,
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 14, height: 1.6, fontWeight: FontWeight.w500),
                                  h1: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                  h2: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                                  h3: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                  code: TextStyle(backgroundColor: AgentHubTheme.pillBackground, color: AgentHubTheme.titleRed, fontSize: 12, fontWeight: FontWeight.w600),
                                  codeblockDecoration: BoxDecoration(
                                    color: AgentHubTheme.pillBackground,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AgentHubTheme.border),
                                  ),
                                  blockquoteDecoration: BoxDecoration(
                                    color: AgentHubTheme.pillBackground,
                                    borderRadius: BorderRadius.circular(6),
                                    border: const Border(
                                      left: BorderSide(color: AgentHubTheme.primaryRed, width: 3),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: message.content));
                              setState(() => _copiedMessageId = message.id);
                              Future.delayed(const Duration(milliseconds: 1500), () {
                                if (mounted && _copiedMessageId == message.id) {
                                  setState(() => _copiedMessageId = null);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AgentHubTheme.cardBackground,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AgentHubTheme.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _copiedMessageId == message.id ? Icons.check : Icons.content_copy_outlined,
                                    size: 13,
                                    color: _copiedMessageId == message.id ? AgentHubTheme.statusGreen : AgentHubTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _copiedMessageId == message.id ? '已复制' : '复制',
                                    style: TextStyle(
                                      color: _copiedMessageId == message.id ? AgentHubTheme.statusGreen : AgentHubTheme.textSecondary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!isUser && message.status == MessageStatus.error) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: provider.isBusy ? null : () => provider.retryLastMessage(),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AgentHubTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AgentHubTheme.primaryRed.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh, size: 13, color: AgentHubTheme.primaryRed),
                                    const SizedBox(width: 4),
                                    Text('重试', style: TextStyle(color: AgentHubTheme.primaryRed, fontSize: 11, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                // 用户头像：使用 Icons 替代文本 'U'
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AgentHubTheme.primaryRed, borderRadius: BorderRadius.circular(8)),
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

  /// 底部输入区（支持 Enter 发送，Shift+Enter 换行；微信会话自动禁用）
  Widget _buildInputArea(AppStateProvider provider) {
    final activeSession = provider.sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == provider.activeSessionId,
      orElse: () => null,
    );
    final isWechatSession = activeSession?.channel == 'wechat';
    final isInputDisabled = provider.isBusy || isWechatSession;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: AgentHubTheme.background,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isWechatSession ? AgentHubTheme.background : AgentHubTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgentHubTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  if (isInputDisabled) {
                    return KeyEventResult.ignored;
                  }
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
                  enabled: !isInputDisabled,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(
                    color: isWechatSession ? AgentHubTheme.textTertiary : AgentHubTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: isWechatSession ? '微信会话暂不支持输入' : '输入内容...',
                    hintStyle: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13),
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
                  foregroundColor: AgentHubTheme.primaryRed,
                  side: const BorderSide(color: AgentHubTheme.primaryRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('停止', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton(
              onPressed: isInputDisabled ? null : _handleSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: isWechatSession ? AgentHubTheme.pillBackground : AgentHubTheme.primaryRed,
                foregroundColor: isWechatSession ? AgentHubTheme.textTertiary : Colors.white,
                disabledBackgroundColor: AgentHubTheme.pillBackground,
                disabledForegroundColor: AgentHubTheme.textTertiary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(
                provider.isBusy ? '处理中' : '发送',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

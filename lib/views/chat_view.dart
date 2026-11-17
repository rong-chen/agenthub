import 'package:flutter/material.dart';
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

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
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

  /// 滚动到最新消息位置
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final messages = provider.messages;

    return Container(
      color: OpenClawTheme.background,
      child: Column(
        children: [
          _buildHeaderRow(provider),
          Divider(height: 1, thickness: 1, color: OpenClawTheme.divider),
          Expanded(
            child: messages.isEmpty ? _buildEmptyState() : _buildMessageList(messages),
          ),
          _buildInputArea(provider),
        ],
      ),
    );
  }

  /// 页面标题
  Widget _buildHeaderRow(AppStateProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      color: OpenClawTheme.headerBackground,
      child: Row(
        children: [
          Expanded(
            child: Text('主页', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: OpenClawTheme.titleRed)),
          ),
          OutlinedButton(
            onPressed: () => provider.clearChatHistory(),
            style: OutlinedButton.styleFrom(
              foregroundColor: OpenClawTheme.textSecondary,
              backgroundColor: OpenClawTheme.cardBackground,
              side: BorderSide(color: OpenClawTheme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('清空会话', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: OpenClawTheme.primaryRedLight,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.chat_bubble_outline, size: 24, color: OpenClawTheme.primaryRed),
          ),
          const SizedBox(height: 14),
          Text('有什么可以帮你的?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: OpenClawTheme.textPrimary)),
          const SizedBox(height: 6),
          Text('在下方输入框中键入指令开始交互', style: TextStyle(fontSize: 13, color: OpenClawTheme.textSecondary)),
        ],
      ),
    );
  }

  /// 消息列表
  Widget _buildMessageList(List<ChatMessageModel> messages) {
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
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: OpenClawTheme.pillBackground, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Text('A', style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? OpenClawTheme.primaryRedLight : OpenClawTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OpenClawTheme.border),
                  ),
                  child: isUser
                      ? Text(message.content, style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14, height: 1.5))
                      : MarkdownBody(
                          data: message.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14, height: 1.6),
                            code: TextStyle(backgroundColor: OpenClawTheme.pillBackground, color: OpenClawTheme.titleRed, fontSize: 12),
                            codeblockDecoration: BoxDecoration(
                              color: OpenClawTheme.pillBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: OpenClawTheme.border),
                            ),
                          ),
                        ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: OpenClawTheme.primaryRed, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: const Text('U', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 底部输入区
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
              child: TextField(
                controller: _inputController,
                enabled: !provider.isBusy,
                maxLines: 4,
                minLines: 1,
                style: TextStyle(color: OpenClawTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '输入指令或提问...',
                  hintStyle: TextStyle(color: OpenClawTheme.textTertiary, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) => _handleSend(),
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
              child: Text(provider.isBusy ? '输出中...' : '发送', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/attachment.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../providers/app_state_provider.dart';
import '../services/attachment_service.dart';
import '../services/database_service.dart';
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
  final List<Attachment> _attachments = [];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// 选择附件 (图片或文档)
  Future<void> _pickAttachments() async {
    final activeSession = context.read<AppStateProvider>().sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == context.read<AppStateProvider>().activeSessionId,
      orElse: () => null,
    );
    final workDir = activeSession?.workDir ?? Directory.current.path;

    final files = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (files.isEmpty) return;

    for (final f in files) {
      final path = f.path;
      if (path != null && File(path).existsSync()) {
        final att = await AttachmentService.instance.stageFile(
          sourcePath: path,
          instanceWorkDir: workDir,
        );
        _attachments.add(att);
      }
    }
    setState(() {});
  }

  /// 发送消息处理
  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) {
      return;
    }
    final provider = context.read<AppStateProvider>();
    if (provider.isBusy) {
      return;
    }
    final attachmentsToSend = List<Attachment>.from(_attachments);
    _attachments.clear();
    provider.sendMessage(text, attachments: attachmentsToSend);
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
          _buildTopBar(provider),
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

  /// 会话状态顶栏
  Widget _buildTopBar(AppStateProvider provider) {
    final activeSession = provider.sessions.cast<ChatSessionModel?>().firstWhere(
      (s) => s?.id == provider.activeSessionId,
      orElse: () => null,
    );
    if (activeSession == null) return const SizedBox.shrink();

    final isCode = activeSession.isCodeMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AgentHubTheme.cardBackground,
        border: Border(bottom: BorderSide(color: AgentHubTheme.divider)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isCode ? AgentHubTheme.primaryRed : AgentHubTheme.border,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isCode ? '代码模式 · Claude Code' : '聊天模式',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isCode ? Colors.white : AgentHubTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              activeSession.title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCode) ...[
            Icon(Icons.folder_outlined, size: 14, color: AgentHubTheme.textTertiary),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                activeSession.workDir ?? '未指定目录',
                style: TextStyle(fontSize: 11, color: AgentHubTheme.textTertiary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () async {
                String? selectedPath;
                try {
                  final uri = await FilePicker.pickDirectory(dialogTitle: '更改工作目录');
                  selectedPath = uri?.toFilePath();
                } catch (e) {
                  debugPrint('更改目录失败: $e');
                }
                if (selectedPath != null && selectedPath.isNotEmpty) {
                  var clean = selectedPath.trim();
                  while ((clean.endsWith('/') || clean.endsWith(r'\')) && clean.length > 1) {
                    clean = clean.substring(0, clean.length - 1);
                  }
                  activeSession.workDir = clean;
                  await DatabaseService.instance.updateSession(activeSession);
                  setState(() {});
                }
              },
              child: Icon(Icons.edit_outlined, size: 14, color: AgentHubTheme.textSecondary),
            ),
          ],
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
                      if (message.attachments != null && message.attachments!.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: message.attachments!.map((fileName) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: AgentHubTheme.cardBackground,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AgentHubTheme.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.insert_drive_file_outlined, size: 12, color: AgentHubTheme.primaryRed),
                                  const SizedBox(width: 4),
                                  Text(fileName, style: TextStyle(fontSize: 11, color: AgentHubTheme.textPrimary)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (message.toolName != null && message.toolName!.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AgentHubTheme.isDark ? const Color(0xFF161616) : const Color(0xFFF2F2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AgentHubTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.terminal_outlined, size: 13, color: AgentHubTheme.primaryRed),
                                  const SizedBox(width: 4),
                                  Text(
                                    '执行工具: ${message.toolName}',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary),
                                  ),
                                ],
                              ),
                              if (message.toolInput != null && message.toolInput!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  message.toolInput!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: AgentHubTheme.isDark ? const Color(0xFFE0E0E0) : const Color(0xFF222222),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              if (message.toolOutput != null && message.toolOutput!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  message.toolOutput!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: AgentHubTheme.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (message.isThinking || (message.thinking != null && message.thinking!.isNotEmpty)) ...[
                        _ThinkingCard(
                          thinking: message.thinking,
                          isThinking: message.isThinking,
                        ),
                      ],
                      if (message.toolName != null && message.toolName!.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AgentHubTheme.isDark ? const Color(0xFF161616) : const Color(0xFFF2F2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AgentHubTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.terminal_outlined, size: 13, color: AgentHubTheme.primaryRed),
                                  const SizedBox(width: 4),
                                  Text(
                                    '执行工具: ${message.toolName}',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary),
                                  ),
                                ],
                              ),
                              if (message.toolInput != null && message.toolInput!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  message.toolInput!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: AgentHubTheme.isDark ? const Color(0xFFE0E0E0) : const Color(0xFF222222),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              if (message.toolOutput != null && message.toolOutput!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  message.toolOutput!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: AgentHubTheme.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (isUser || message.content.isNotEmpty || message.status == MessageStatus.streaming || message.status == MessageStatus.error) ...[
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
                              : message.content.isEmpty
                                  ? (message.status == MessageStatus.streaming
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: AgentHubTheme.primaryRed),
                                            ),
                                            const SizedBox(width: 8),
                                            Text('正在处理任务...', style: TextStyle(color: AgentHubTheme.textSecondary, fontSize: 13)),
                                          ],
                                        )
                                      : Text(
                                          '执行异常',
                                          style: TextStyle(color: AgentHubTheme.primaryRed, fontSize: 13),
                                        ))
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
                      ],
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.checkpoint != null && message.checkpoint!.changedFiles.isNotEmpty) ...[
                            InkWell(
                              onTap: () {
                                if (provider.rightPanelType == RightPanelType.fileDiff &&
                                    provider.activeCheckpoint?.id == message.checkpoint!.id) {
                                  provider.closeRightPanel();
                                } else {
                                  provider.openFileDiffPanel(message.checkpoint!, message);
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (provider.rightPanelType == RightPanelType.fileDiff &&
                                          provider.activeCheckpoint?.id == message.checkpoint!.id)
                                      ? AgentHubTheme.primaryRed.withValues(alpha: 0.1)
                                      : AgentHubTheme.cardBackground,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: (provider.rightPanelType == RightPanelType.fileDiff &&
                                            provider.activeCheckpoint?.id == message.checkpoint!.id)
                                        ? AgentHubTheme.primaryRed
                                        : AgentHubTheme.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.difference_outlined,
                                      size: 13,
                                      color: (provider.rightPanelType == RightPanelType.fileDiff &&
                                              provider.activeCheckpoint?.id == message.checkpoint!.id)
                                          ? AgentHubTheme.primaryRed
                                          : AgentHubTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '查看改动',
                                      style: TextStyle(
                                        color: (provider.rightPanelType == RightPanelType.fileDiff &&
                                                provider.activeCheckpoint?.id == message.checkpoint!.id)
                                            ? AgentHubTheme.primaryRed
                                            : AgentHubTheme.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: (message.checkpoint!.isRolledBack || provider.isBusy)
                                  ? null
                                  : () => _confirmRollback(provider, message),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: message.checkpoint!.isRolledBack
                                      ? AgentHubTheme.cardBackground
                                      : AgentHubTheme.primaryRed.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: message.checkpoint!.isRolledBack
                                        ? AgentHubTheme.border
                                        : AgentHubTheme.primaryRed.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.undo,
                                      size: 13,
                                      color: message.checkpoint!.isRolledBack
                                          ? AgentHubTheme.textTertiary
                                          : AgentHubTheme.primaryRed,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      message.checkpoint!.isRolledBack ? '已回退' : '回退',
                                      style: TextStyle(
                                        color: message.checkpoint!.isRolledBack
                                            ? AgentHubTheme.textTertiary
                                            : AgentHubTheme.primaryRed,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
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

  /// 弹出确认回滚对话框
  void _confirmRollback(AppStateProvider provider, ChatMessageModel message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AgentHubTheme.cardBackground,
        title: const Text('确认回退改动', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text(
          '是否确定将本次任务修改的文件恢复到执行前的状态？',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(color: AgentHubTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await provider.rollbackMessageCheckpoint(message);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AgentHubTheme.primaryRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认回退'),
          ),
        ],
      ),
    );
  }

  /// 底部输入区（支持 Enter 发送，Shift+Enter 换行；支持文件/图片上传；微信会话自动禁用）
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachments.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _attachments.map((att) {
                return Container(
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
                        att.type == AttachmentType.image ? Icons.image_outlined : Icons.insert_drive_file_outlined,
                        size: 14,
                        color: AgentHubTheme.primaryRed,
                      ),
                      const SizedBox(width: 4),
                      Text(att.fileName, style: TextStyle(fontSize: 11, color: AgentHubTheme.textPrimary)),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => setState(() => _attachments.remove(att)),
                        child: Icon(Icons.close, size: 12, color: AgentHubTheme.textTertiary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isWechatSession ? AgentHubTheme.background : AgentHubTheme.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AgentHubTheme.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isWechatSession) ...[
                  IconButton(
                    icon: Icon(Icons.attach_file, size: 18, color: AgentHubTheme.textSecondary),
                    tooltip: '添加图片或文件',
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    constraints: const BoxConstraints(),
                    onPressed: isInputDisabled ? null : _pickAttachments,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (isInputDisabled) {
                        return KeyEventResult.ignored;
                      }
                      if (_inputController.value.isComposingRangeValid) {
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
                        hintText: isWechatSession ? '微信会话暂不支持输入' : (activeSession?.isCodeMode == true ? '输入指令，调用 Claude Code 改代码...' : '输入内容...'),
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
        ],
      ),
    );
  }
}

/// 可折叠的思考过程卡片
class _ThinkingCard extends StatefulWidget {
  final String? thinking;
  final bool isThinking;

  const _ThinkingCard({
    required this.thinking,
    required this.isThinking,
  });

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasText = widget.thinking != null && widget.thinking!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AgentHubTheme.isDark ? const Color(0xFF1B1B1B) : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgentHubTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasText ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isThinking ? Icons.psychology_outlined : Icons.lightbulb_outline,
                    size: 14,
                    color: AgentHubTheme.primaryRed,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isThinking ? '深度思考中...' : '已完成思考',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AgentHubTheme.textSecondary,
                    ),
                  ),
                  if (hasText) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 14,
                      color: AgentHubTheme.textTertiary,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && hasText)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SelectableText(
                widget.thinking!,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: AgentHubTheme.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

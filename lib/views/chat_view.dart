import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../models/attachment.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../models/tool_step_model.dart';
import '../providers/app_state_provider.dart';
import '../services/attachment_service.dart';
import '../services/project_service_manager.dart';
import '../theme/agenthub_theme.dart';
import '../widgets/app_text_field.dart';
import 'components/tool_steps_card.dart';

/// 对话交互视图
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _inputController = AppTextEditingController();
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

  bool _isScrolling = false;

  /// 滚动到消息底部
  void _scrollToBottom({bool animate = true}) {
    if (_isScrolling && animate) return;

    void execute() {
      if (!_scrollController.hasClients) {
        return;
      }
      final pos = _scrollController.position;
      final target = pos.maxScrollExtent;
      if (target <= 0) {
        return;
      }
      if ((pos.pixels - target).abs() < 2) {
        return;
      }
      if (animate) {
        _isScrolling = true;
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ).then((_) {
          _isScrolling = false;
        }).catchError((_) {
          _isScrolling = false;
        });
      } else {
        _scrollController.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      execute();
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
    } else if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom(animate: true);
    } else if (provider.isBusy) {
      // 流式输出中无动画瞬时定位，避免动画队列堆积产生卡顿
      _scrollToBottom(animate: false);
    }

    if (provider.pendingInputPrompt != null) {
      final prompt = provider.consumePendingInputPrompt();
      if (prompt != null && prompt.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inputController.text = prompt;
          _inputController.selection = TextSelection.collapsed(offset: prompt.length);
          _inputFocusNode.requestFocus();
        });
      }
    }

    return Container(
      color: provider.isDarkTheme ? const Color(0xFF181818) : const Color(0xFFF9F8F5),
      child: Column(
        children: [
          _buildActiveServiceBanner(provider),
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

  /// 本地常驻服务（如 npm run dev）运行状态横幅，提供一键停止与控制台跳转
  Widget _buildActiveServiceBanner(AppStateProvider provider) {
    final session = provider.activeSession;
    if (session == null) return const SizedBox.shrink();
    final service = ProjectServiceManager.instance.getInstance(session.id);
    if (service == null || !service.isRunning) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AgentHubTheme.cardBackground,
        border: Border(bottom: BorderSide(color: AgentHubTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_fill, size: 16, color: Color(0xFF2EA44F)),
          const SizedBox(width: 8),
          Text(
            '本地服务运行中:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AgentHubTheme.textPrimary),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AgentHubTheme.pillBackground,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              service.command,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: AgentHubTheme.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              provider.switchRightPanelTab(RightPanelType.serviceRunner);
            },
            icon: const Icon(Icons.terminal, size: 13),
            label: const Text('控制台', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: AgentHubTheme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              ProjectServiceManager.instance.stopService(session.id);
            },
            icon: const Icon(Icons.stop, size: 13),
            label: const Text('停止服务', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCF222E),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }

  /// 消息列表（从顶部按时间顺序正常向下排列，支持多行划选与右键复制）
  Widget _buildMessageList(AppStateProvider provider, List<ChatMessageModel> messages) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth > 80 ? constraints.maxWidth * 0.88 : constraints.maxWidth;

        return SelectionArea(
          contextMenuBuilder: (context, selectableRegionState) {
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: selectableRegionState.contextMenuAnchors,
              buttonItems: selectableRegionState.contextMenuButtonItems,
            );
          },
          child: ListView.builder(
            key: PageStorageKey<String>('session_${provider.activeSessionId}'),
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
                      // AI 头像
                      SelectionContainer.disabled(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: AgentHubTheme.pillBackground, borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.center,
                          child: Icon(Icons.smart_toy_outlined, size: 18, color: AgentHubTheme.textPrimary),
                        ),
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
                      if (message.isThinking || (message.thinking != null && message.thinking!.isNotEmpty) || message.thinkings.isNotEmpty) ...[
                        _ThinkingCard(
                          thinking: message.thinking,
                          thinkings: message.thinkings,
                          isThinking: message.isThinking,
                        ),
                      ],
                      if (message.toolSteps.isNotEmpty) ...[
                        ToolStepsCard(steps: message.toolSteps),
                      ] else if (message.toolName != null && message.toolName!.isNotEmpty) ...[
                        ToolStepsCard(
                          steps: [
                            ToolStepModel.fromRaw(
                              toolName: message.toolName!,
                              input: message.toolInput,
                              output: message.toolOutput,
                              status: message.status == MessageStatus.error
                                  ? ToolStepStatus.error
                                  : ToolStepStatus.success,
                            ),
                          ],
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
                      // 底部辅助操作条（禁用选择，防止混入选中复制）
                      SelectionContainer.disabled(
                        child: Row(
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
                      ),
                    ],
                  ),
                ),
              ),
              if (isUser) ...[
                const SizedBox(width: 10),
                // 用户头像（禁用选择）
                SelectionContainer.disabled(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: AgentHubTheme.primaryRed, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person_outlined, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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
              final revertedPrompt = await provider.rollbackMessageCheckpoint(message);
              if (revertedPrompt != null && revertedPrompt.trim().isNotEmpty) {
                _inputController.text = revertedPrompt;
                _inputController.selection = TextSelection.collapsed(offset: revertedPrompt.length);
                _inputFocusNode.requestFocus();
              }
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
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
                      cursorWidth: 1.5,
                      cursorRadius: const Radius.circular(1),
                      maxLines: 4,
                      minLines: 1,
                      style: TextStyle(
                        color: isWechatSession ? AgentHubTheme.textTertiary : AgentHubTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                      ),
                      decoration: InputDecoration(
                        hintText: isWechatSession ? '微信会话暂不支持输入' : (activeSession?.isCodeMode == true ? '输入指令，调用 Claude Code 改代码...' : '输入内容...'),
                        hintStyle: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13, letterSpacing: 0.8),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isWechatSession) ...[
                  IconButton(
                    icon: Icon(Icons.attach_file, size: 20, color: AgentHubTheme.textSecondary),
                    tooltip: '添加图片或文件',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: isInputDisabled ? null : _pickAttachments,
                  ),
                  const SizedBox(width: 8),
                ],
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

/// 可折叠的思考过程卡片（支持多阶段思考完整展示，绝不覆盖）
class _ThinkingCard extends StatefulWidget {
  final String? thinking;
  final List<String> thinkings;
  final bool isThinking;

  const _ThinkingCard({
    this.thinking,
    this.thinkings = const [],
    required this.isThinking,
  });

  @override
  State<_ThinkingCard> createState() => _ThinkingCardState();
}

class _ThinkingCardState extends State<_ThinkingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final phases = widget.thinkings.isNotEmpty
        ? widget.thinkings
        : (widget.thinking != null && widget.thinking!.trim().isNotEmpty ? [widget.thinking!] : <String>[]);
    final hasText = phases.isNotEmpty;
    final phaseCount = phases.length;

    String title;
    if (widget.isThinking) {
      title = phaseCount > 1 ? '深度思考中 (第 $phaseCount 阶段)...' : '深度思考中...';
    } else {
      title = phaseCount > 1 ? '已完成思考 ($phaseCount 个阶段)' : '已完成思考';
    }

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
                    title,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < phases.length; i++) ...[
                    if (phases.length > 1) ...[
                      if (i > 0)
                        Divider(height: 14, thickness: 1, color: AgentHubTheme.border),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: AgentHubTheme.pillBackground,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '阶段 ${i + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AgentHubTheme.primaryRed,
                          ),
                        ),
                      ),
                    ],
                    SelectableText(
                      phases[i],
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AgentHubTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

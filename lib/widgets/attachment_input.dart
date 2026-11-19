import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';
import '../models/attachment.dart';
import '../services/attachment_service.dart';
import '../theme/agenthub_theme.dart';

/// 包含附件选择、拖拽、粘贴和发送的输入组件
class AttachmentInput extends StatefulWidget {
  final String workDir;
  final bool isBusy;
  final Function(String text, List<Attachment> attachments) onSend;
  final VoidCallback? onAbort;

  const AttachmentInput({
    super.key,
    required this.workDir,
    required this.isBusy,
    required this.onSend,
    this.onAbort,
  });

  @override
  State<AttachmentInput> createState() => _AttachmentInputState();
}

class _AttachmentInputState extends State<AttachmentInput> {
  final TextEditingController _textController = TextEditingController();
  final List<Attachment> _attachments = [];
  bool _isDragging = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 打开系统文件选择器
  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.any,
    );

    if (files.isEmpty) return;

    for (final file in files) {
      final path = file.path;
      if (path != null && File(path).existsSync()) {
        final att = await AttachmentService.instance.stageFile(
          sourcePath: path,
          instanceWorkDir: widget.workDir,
        );
        setState(() {
          _attachments.add(att);
        });
      }
    }
  }

  /// 从剪贴板粘贴图片
  Future<void> _pasteFromClipboard() async {
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null) {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/pasted_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(imageBytes);

      final att = await AttachmentService.instance.stageFile(
        sourcePath: tempFile.path,
        instanceWorkDir: widget.workDir,
      );
      setState(() {
        _attachments.add(att);
      });
    }
  }

  /// 移除指定附件
  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  /// 触发发送
  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.isBusy) return;

    widget.onSend(text, List.from(_attachments));
    _textController.clear();
    setState(() {
      _attachments.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (detail) async {
        setState(() => _isDragging = false);
        for (final file in detail.files) {
          if (File(file.path).existsSync()) {
            final att = await AttachmentService.instance.stageFile(
              sourcePath: file.path,
              instanceWorkDir: widget.workDir,
            );
            setState(() {
              _attachments.add(att);
            });
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AgentHubTheme.cardBackground,
          border: Border.all(
            color: _isDragging ? AgentHubTheme.primaryRed : AgentHubTheme.border,
            width: _isDragging ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 附件预览栏
            if (_attachments.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: List.generate(_attachments.length, (idx) {
                  final att = _attachments[idx];
                  return _buildAttachmentTag(att, idx);
                }),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: AgentHubTheme.divider),
              const SizedBox(height: 6),
            ],
            // 文本输入区与工具按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLines: 4,
                    minLines: 1,
                    style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入任务指令，支持粘贴剪贴板图片或拖入文件...',
                      hintStyle: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                // 粘贴图片按钮
                IconButton(
                  tooltip: '粘贴剪贴板图片',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.content_paste_outlined, size: 18, color: AgentHubTheme.textSecondary),
                  onPressed: widget.isBusy ? null : _pasteFromClipboard,
                ),
                const SizedBox(width: 8),
                // 选择文件/图片按钮
                IconButton(
                  tooltip: '添加文件或图片',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.attach_file_outlined, size: 18, color: AgentHubTheme.textSecondary),
                  onPressed: widget.isBusy ? null : _pickFiles,
                ),
                const SizedBox(width: 8),
                // 发送或中止按钮
                if (widget.isBusy && widget.onAbort != null)
                  ElevatedButton(
                    onPressed: widget.onAbort,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgentHubTheme.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('中止', style: TextStyle(fontSize: 12)),
                  )
                else
                  ElevatedButton(
                    onPressed: _handleSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AgentHubTheme.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('发送', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 附件预览徽标
  Widget _buildAttachmentTag(Attachment att, int index) {
    IconData iconData;
    if (att.type == AttachmentType.image) {
      iconData = Icons.image_outlined;
    } else if (att.type == AttachmentType.code) {
      iconData = Icons.code_outlined;
    } else {
      iconData = Icons.insert_drive_file_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AgentHubTheme.pillBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AgentHubTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: AgentHubTheme.primaryRed),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              att.fileName,
              style: TextStyle(color: AgentHubTheme.textPrimary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            att.formattedSize,
            style: TextStyle(color: AgentHubTheme.textTertiary, fontSize: 10),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _removeAttachment(index),
            child: Icon(Icons.close, size: 12, color: AgentHubTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

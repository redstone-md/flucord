import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

typedef SendMessageCallback =
    Future<bool> Function(
      String body,
      List<PendingAttachment> attachments,
      String? replyToMessageId,
    );

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.channelName,
    required this.isSending,
    required this.onSend,
    required this.onCancelReply,
    this.replyTo,
    this.replyAuthor,
    super.key,
  });

  final String channelName;
  final bool isSending;
  final SendMessageCallback onSend;
  final ChatMessage? replyTo;
  final Member? replyAuthor;
  final VoidCallback onCancelReply;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<PendingAttachment> _attachments = [];
  bool _hasContent = false;

  bool get _canSend => _hasContent || _attachments.isNotEmpty;

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelName != widget.channelName) {
      _controller.clear();
      _attachments.clear();
      _hasContent = false;
    }
    if (oldWidget.replyTo?.id != widget.replyTo?.id && widget.replyTo != null) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Attach files',
        allowMultiple: true,
        lockParentWindow: true,
      );
      if (!mounted || result == null) return;
      setState(() {
        for (final file in result.files) {
          final path = file.path;
          if (path == null || _attachments.any((item) => item.path == path)) {
            continue;
          }
          _attachments.add(
            PendingAttachment(name: file.name, path: path, size: file.size),
          );
        }
      });
      _focusNode.requestFocus();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file picker could not be opened.')),
      );
    }
  }

  Future<void> _send() async {
    if (!_canSend || widget.isSending) return;
    final sent = await widget.onSend(
      _controller.text,
      List.unmodifiable(_attachments),
      widget.replyTo?.id,
    );
    if (!mounted || !sent) return;
    _controller.clear();
    setState(() {
      _hasContent = false;
      _attachments.clear();
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: context.surfaces.canvas,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyTo != null) _replyBar(context),
          if (_attachments.isNotEmpty) _attachmentStrip(context),
          CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
            child: Focus(
              autofocus: true,
              child: TextField(
                key: const ValueKey('message-composer'),
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                onChanged: (value) {
                  final hasContent = value.trim().isNotEmpty;
                  if (hasContent != _hasContent) {
                    setState(() => _hasContent = hasContent);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Message #${widget.channelName}',
                  contentPadding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                  prefixIcon: IconButton(
                    key: const ValueKey('add-attachment'),
                    onPressed: widget.isSending ? null : _pickAttachments,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    tooltip: 'Add attachment',
                  ),
                  suffixIcon: widget.isSending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('send-message'),
                          onPressed: _canSend ? _send : null,
                          icon: Icon(
                            Icons.send,
                            size: 19,
                            color: _canSend ? FlucordColors.signal : null,
                          ),
                          tooltip: 'Send message',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyBar(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      color: context.surfaces.surface,
      border: Border(
        top: BorderSide(color: context.surfaces.border),
        left: BorderSide(color: context.surfaces.border),
        right: BorderSide(color: context.surfaces.border),
      ),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    ),
    child: Row(
      children: [
        Icon(Icons.reply, size: 14, color: context.surfaces.muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Replying to ${widget.replyAuthor?.displayName ?? 'Unknown user'}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        IconButton(
          onPressed: widget.onCancelReply,
          icon: const Icon(Icons.close, size: 16),
          tooltip: 'Cancel reply',
        ),
      ],
    ),
  );

  Widget _attachmentStrip(BuildContext context) => Container(
    height: 54,
    margin: const EdgeInsets.only(bottom: 6),
    alignment: Alignment.centerLeft,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _attachments.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final attachment = _attachments[index];
        return Container(
          width: 190,
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: context.surfaces.inset,
            border: Border.all(color: context.surfaces.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 18,
                color: context.surfaces.muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _attachments.removeAt(index)),
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Remove attachment',
              ),
            ],
          ),
        );
      },
    ),
  );
}

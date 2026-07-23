import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/flucord_theme.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.channelName,
    required this.isSending,
    required this.onSend,
    super.key,
  });

  final String channelName;
  final bool isSending;
  final Future<bool> Function(String body) onSend;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasContent = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_hasContent || widget.isSending) return;
    final sent = await widget.onSend(_controller.text);
    if (!mounted || !sent) return;
    _controller.clear();
    setState(() => _hasContent = false);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: context.surfaces.canvas,
      child: CallbackShortcuts(
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
                onPressed: () {},
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
                      onPressed: _hasContent ? _send : null,
                      icon: Icon(
                        Icons.send,
                        size: 19,
                        color: _hasContent ? FlucordColors.signal : null,
                      ),
                      tooltip: 'Send message',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

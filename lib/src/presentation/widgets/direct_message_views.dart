import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DirectMessageDialog extends StatefulWidget {
  const DirectMessageDialog({super.key});

  @override
  State<DirectMessageDialog> createState() => _DirectMessageDialogState();
}

class _DirectMessageDialogState extends State<DirectMessageDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (!RegExp(r'^\d{17,20}$').hasMatch(value)) {
      setState(() => _error = 'Enter a valid Discord user ID');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New message'),
    content: SizedBox(
      width: 360,
      child: TextField(
        key: const ValueKey('direct-message-user-id'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: 'Discord user ID',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.chat_bubble_outline, size: 16),
        label: const Text('Open'),
      ),
    ],
  );
}

class DirectMessagesEmptyView extends StatelessWidget {
  const DirectMessagesEmptyView({required this.onNewMessage, super.key});

  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.forum_outlined,
          size: 34,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        const Text(
          'No direct messages',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onNewMessage,
          icon: const Icon(Icons.edit_square, size: 16),
          label: const Text('New message'),
        ),
      ],
    ),
  );
}

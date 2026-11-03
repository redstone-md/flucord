import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'flucord_dialog.dart';

/// Discord's create-a-server dialog: a name in, a server out, owned by this
/// account and ready to configure.
class CreateServerDialog extends StatefulWidget {
  const CreateServerDialog({required this.chat, super.key});

  final ChatController chat;

  @override
  State<CreateServerDialog> createState() => _CreateServerDialogState();
}

class _CreateServerDialogState extends State<CreateServerDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the server a name.');
      return;
    }
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final spaceId = await widget.chat.createGuild(name);
      if (!mounted) return;
      if (spaceId == null) {
        setState(() {
          _creating = false;
          _error =
              widget.chat.guildAccessError ?? 'The server was not created.';
        });
        return;
      }
      Navigator.of(context).pop(spaceId);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error is! StateError ? error.toString() : error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('create-server-dialog'),
    maxWidth: 480,
    title: const Text('Create a server'),
    description:
        'Your server is where you and your friends hang out. Name it now; '
        'everything else can be changed later.',
    content: FlucordTextField(
      fieldKey: const ValueKey('create-server-name-field'),
      label: 'Server name',
      controller: _controller,
      autofocus: true,
      enabled: !_creating,
      maxLength: 100,
      errorText: _error,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => unawaited(_create()),
    ),
    onConfirm: () => unawaited(_create()),
    actions: [
      FlucordButton(
        label: 'Cancel',
        keyHint: FlucordKeyHint.escape,
        onPressed: () => Navigator.of(context).pop(),
      ),
      FlucordButton(
        key: const ValueKey('create-server-submit'),
        kind: FlucordButtonKind.primary,
        label: _creating ? 'Creating' : 'Create',
        keyHint: FlucordKeyHint.enter,
        onPressed: _creating ? null : () => unawaited(_create()),
      ),
    ],
  );
}

/// Opens the create dialog. Answers the new space's id.
Future<String?> showCreateServerDialog(
  BuildContext context, {
  required ChatController chat,
}) => showDialog<String>(
  context: context,
  builder: (_) => CreateServerDialog(chat: chat),
);

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_friends_controller.dart';
import '../../theme/flucord_theme.dart';

Future<void> showDiscordAddFriendDialog(
  BuildContext context,
  DiscordFriendsController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _DiscordAddFriendDialog(controller: controller),
);

class _DiscordAddFriendDialog extends StatefulWidget {
  const _DiscordAddFriendDialog({required this.controller});

  final DiscordFriendsController controller;

  @override
  State<_DiscordAddFriendDialog> createState() =>
      _DiscordAddFriendDialogState();
}

class _DiscordAddFriendDialogState extends State<_DiscordAddFriendDialog> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.clearFriendRequestError();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final succeeded = await widget.controller.sendFriendRequest(
      _textController.text,
    );
    if (succeeded && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final sending = widget.controller.isSendingFriendRequest;
        final error = widget.controller.friendRequestError;
        return AlertDialog(
          key: const ValueKey('discord-add-friend-dialog'),
          backgroundColor: context.surfaces.surface,
          title: const Text('Add Friend'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter their Discord user ID to send a standard friend request.',
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('discord-add-friend-user-id'),
                  controller: _textController,
                  focusNode: _focusNode,
                  autofocus: true,
                  enabled: !sending,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.send,
                  maxLength: 20,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Discord user ID',
                    hintText: '123456789012345678',
                    counterText: '',
                  ),
                  onChanged: (_) {
                    widget.controller.clearFriendRequestError();
                    setState(() {});
                  },
                  onSubmitted: (_) {
                    if (!sending && _textController.text.isNotEmpty) {
                      unawaited(_submit());
                    }
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 9),
                  Text(
                    _errorLabel(error),
                    key: const ValueKey('discord-add-friend-error'),
                    style: const TextStyle(
                      color: FlucordColors.danger,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('discord-add-friend-submit'),
              onPressed: sending || _textController.text.isEmpty
                  ? null
                  : _submit,
              child: sending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Friend Request'),
            ),
          ],
        );
      },
    );
  }
}

String _errorLabel(String code) => switch (code) {
  'invalid_user_id' => 'Enter a valid numeric Discord user ID.',
  'not_authenticated' => 'Reconnect the native Discord account and try again.',
  'friend_request_failed' =>
    'Discord did not accept this friend request. Check the user ID.',
  _ => 'Friend request failed. Try again.',
};

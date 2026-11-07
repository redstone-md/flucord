import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'flucord_dialog.dart';
import 'invite_limit_fields.dart';

/// Opens Invite people for [space]: a ready link into [channel], a copy
/// button, and the expiry and use-cap choices.
///
/// Any member with CREATE_INSTANT_INVITE may do this; the caller decides
/// that before it offers the menu row. [createInvite] makes a link with the
/// options asked for.
Future<void> showInvitePeopleDialog(
  BuildContext context, {
  required CommunitySpace space,
  required ConversationChannel channel,
  required Future<GuildInvite> Function(InviteOptions options) createInvite,
}) => showDialog<void>(
  context: context,
  builder: (_) => _InvitePeopleDialog(
    space: space,
    channel: channel,
    createInvite: createInvite,
  ),
);

class _InvitePeopleDialog extends StatefulWidget {
  const _InvitePeopleDialog({
    required this.space,
    required this.channel,
    required this.createInvite,
  });

  final CommunitySpace space;
  final ConversationChannel channel;
  final Future<GuildInvite> Function(InviteOptions options) createInvite;

  @override
  State<_InvitePeopleDialog> createState() => _InvitePeopleDialogState();
}

class _InvitePeopleDialogState extends State<_InvitePeopleDialog> {
  // Discord's own dialog starts here: seven days, any number of uses. An
  // invite that is not unique lets Discord hand back a matching one, so
  // changing a choice back and forth does not pile up new links.
  int _maxAge = 604800;
  int _maxUses = 0;

  GuildInvite? _invite;
  bool _failed = false;
  bool _copied = false;

  /// Counts asks, so an answer that a newer ask overtook is dropped.
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_makeLink());
  }

  Future<void> _makeLink() async {
    final ask = ++_ask;
    setState(() {
      _invite = null;
      _failed = false;
      _copied = false;
    });
    try {
      final invite = await widget.createInvite(
        InviteOptions(maxAgeSeconds: _maxAge, maxUses: _maxUses),
      );
      if (mounted && ask == _ask) setState(() => _invite = invite);
    } on Object {
      if (mounted && ask == _ask) setState(() => _failed = true);
    }
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('invite-people-dialog'),
    title: Text('Invite friends to ${widget.space.name}'),
    description: 'The link leads to #${widget.channel.name}.',
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _link(context),
          const SizedBox(height: 16),
          InviteLimitFields(
            keyPrefix: 'invite-people',
            maxAgeSeconds: _maxAge,
            maxUses: _maxUses,
            onMaxAgeChanged: (value) {
              _maxAge = value;
              unawaited(_makeLink());
            },
            onMaxUsesChanged: (value) {
              _maxUses = value;
              unawaited(_makeLink());
            },
          ),
        ],
      ),
    ),
    actions: const [FlucordDialogCancel(label: 'Done')],
  );

  Widget _link(BuildContext context) {
    if (_failed) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Discord did not make an invite link.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: FlucordType.caption,
              ),
            ),
          ),
          FlucordButton(
            key: const ValueKey('invite-people-retry'),
            label: 'Try again',
            onPressed: () => unawaited(_makeLink()),
          ),
        ],
      );
    }
    final invite = _invite;
    if (invite == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.surfaces.canvas,
        borderRadius: FlucordRadius.control,
        border: Border.all(color: context.surfaces.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                invite.url,
                key: const ValueKey('invite-people-link'),
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            FlucordButton(
              key: const ValueKey('invite-people-copy'),
              label: _copied ? 'Copied' : 'Copy',
              kind: FlucordButtonKind.primary,
              onPressed: () => unawaited(_copy(invite.url)),
            ),
          ],
        ),
      ),
    );
  }
}

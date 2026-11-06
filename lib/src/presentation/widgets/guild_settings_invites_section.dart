import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
import 'guild_settings_controls.dart';
import 'flucord_dialog.dart';
import 'invite_limit_fields.dart';

/// The invites page: what is outstanding, and how to add or revoke one.
///
/// Creating and revoking are gated separately, because Discord gates them
/// separately: `CREATE_INSTANT_INVITE` is an ordinary member's power and
/// `MANAGE_GUILD` is what it takes to cancel somebody else's.
class GuildSettingsInvitesSection extends StatelessWidget {
  const GuildSettingsInvitesSection({required this.controller, super.key});

  final GuildSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final invites = controller.invites;
    final canRevoke = controller.capabilities.canManageGuild;
    return GuildSettingsPanel(
      title: 'Invites',
      subtitle: 'Every invite link that currently works.',
      trailing: controller.capabilities.canCreateInvite
          ? FilledButton.tonal(
              key: const ValueKey('guild-invite-create'),
              onPressed: controller.isBusy ? null : () => _create(context),
              child: const Text('New invite'),
            )
          : null,
      children: [
        GuildSettingsActionError(error: controller.actionError),
        if (invites.isEmpty)
          const GuildSettingsEmpty(message: 'There are no active invites.')
        else
          for (final invite in invites)
            GuildSettingsRow(
              key: ValueKey('guild-invite-${invite.code}'),
              leading: const FlucordIcon(FlucordIcons.link, size: 16),
              title: invite.code,
              subtitle: _describe(invite),
              trailing: TextButton(
                key: ValueKey('guild-invite-revoke-${invite.code}'),
                onPressed: canRevoke && !controller.isBusy
                    ? () => unawaited(controller.revokeInvite(invite.code))
                    : null,
                child: const Text('Revoke'),
              ),
            ),
      ],
    );
  }

  static String _describe(GuildInvite invite) {
    final uses = invite.hasUnlimitedUses
        ? '${invite.uses} uses'
        : '${invite.uses} of ${invite.maxUses} uses';
    final expiry = invite.neverExpires ? 'never expires' : 'expires';
    final channel = invite.channelName;
    return channel == null ? '$uses - $expiry' : '#$channel - $uses - $expiry';
  }

  Future<void> _create(BuildContext context) async {
    final channels = controller.capabilities.invitableChannels;
    if (channels.isEmpty) return;
    final choice = await showDialog<_InviteChoice>(
      context: context,
      builder: (_) => _CreateInviteDialog(channels: channels),
    );
    if (choice == null) return;
    await controller.createInvite(
      channelId: choice.channelId,
      options: choice.options,
    );
  }
}

final class _InviteChoice {
  const _InviteChoice({required this.channelId, required this.options});

  final String channelId;
  final InviteOptions options;
}

class _CreateInviteDialog extends StatefulWidget {
  const _CreateInviteDialog({required this.channels});

  final List<ConversationChannel> channels;

  @override
  State<_CreateInviteDialog> createState() => _CreateInviteDialogState();
}

class _CreateInviteDialogState extends State<_CreateInviteDialog> {
  late String _channelId = widget.channels.first.id;
  int _maxAge = 86400;
  int _maxUses = 0;
  bool _temporary = false;

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('create-invite-dialog'),
    title: const Text('Create invite'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('create-invite-channel'),
            initialValue: _channelId,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Channel',
            ),
            items: [
              for (final channel in widget.channels)
                DropdownMenuItem(
                  value: channel.id,
                  child: Text(
                    '#${channel.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) =>
                setState(() => _channelId = value ?? _channelId),
          ),
          const SizedBox(height: 10),
          InviteLimitFields(
            keyPrefix: 'create-invite',
            maxAgeSeconds: _maxAge,
            maxUses: _maxUses,
            onMaxAgeChanged: (value) => setState(() => _maxAge = value),
            onMaxUsesChanged: (value) => setState(() => _maxUses = value),
          ),
          SwitchListTile(
            key: const ValueKey('create-invite-temporary'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Grant temporary membership'),
            value: _temporary,
            onChanged: (value) => setState(() => _temporary = value),
          ),
        ],
      ),
    ),
    confirm: FlucordDialogConfirm(
      key: const ValueKey('create-invite-confirm'),
      label: 'Create',
      onPressed: () => Navigator.of(context).pop(
        _InviteChoice(
          channelId: _channelId,
          options: InviteOptions(
            maxAgeSeconds: _maxAge,
            maxUses: _maxUses,
            temporary: _temporary,
            unique: true,
          ),
        ),
      ),
    ),
  );
}

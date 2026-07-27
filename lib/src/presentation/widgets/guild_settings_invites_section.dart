import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
import 'guild_settings_controls.dart';

/// The invites page: what is outstanding, and how to add or revoke one.
///
/// Creating and revoking are gated separately, because Discord gates them
/// separately: `CREATE_INSTANT_INVITE` is an ordinary member's power and
/// `MANAGE_GUILD` is what it takes to cancel somebody else's.
class GuildSettingsInvitesSection extends StatelessWidget {
  const GuildSettingsInvitesSection({
    required this.controller,
    required this.workspace,
    required this.spaceId,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final String spaceId;

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
              leading: const Icon(Icons.link, size: 16),
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
    final channels = workspace
        .channelsFor(spaceId)
        .where(
          (channel) =>
              !channel.isThread &&
              channel.kind == ChannelKind.text &&
              // CREATE_INSTANT_INVITE is routinely granted guild-wide and then
              // taken back per channel, so the guild-wide answer alone would
              // offer channels the server refuses.
              controller.capabilities.canInviteToChannel(channel),
        )
        .toList(growable: false);
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
  Widget build(BuildContext context) => AlertDialog(
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
          DropdownButtonFormField<int>(
            key: const ValueKey('create-invite-expiry'),
            initialValue: _maxAge,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Expires after',
            ),
            items: [
              for (final seconds in InviteOptions.maxAgeChoices)
                DropdownMenuItem(
                  value: seconds,
                  child: Text(_expiryLabel(seconds)),
                ),
            ],
            onChanged: (value) => setState(() => _maxAge = value ?? _maxAge),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            key: const ValueKey('create-invite-uses'),
            initialValue: _maxUses,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Maximum uses',
            ),
            items: [
              for (final uses in InviteOptions.maxUsesChoices)
                DropdownMenuItem(
                  value: uses,
                  child: Text(uses == 0 ? 'No limit' : '$uses uses'),
                ),
            ],
            onChanged: (value) => setState(() => _maxUses = value ?? _maxUses),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('create-invite-confirm'),
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
        child: const Text('Create'),
      ),
    ],
  );

  static String _expiryLabel(int seconds) => switch (seconds) {
    0 => 'Never',
    1800 => '30 minutes',
    3600 => '1 hour',
    21600 => '6 hours',
    43200 => '12 hours',
    86400 => '1 day',
    _ => '7 days',
  };
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
import 'guild_ban_dialog.dart';
import 'guild_settings_controls.dart';

/// The bans page: who is banned, why, and the two ways out and in.
///
/// Banning from here rather than from a member row is a deliberate difference
/// from Discord, which has no bulk path at all in its UI. The bulk route exists
/// on the wire, and a moderator clearing a raid needs it; the picker only
/// offers members this account outranks, so the batch cannot be half-refused.
class GuildSettingsModerationSection extends StatefulWidget {
  const GuildSettingsModerationSection({
    required this.controller,
    required this.workspace,
    required this.spaceId,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final String spaceId;

  @override
  State<GuildSettingsModerationSection> createState() =>
      _GuildSettingsModerationSectionState();
}

class _GuildSettingsModerationSectionState
    extends State<GuildSettingsModerationSection> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final bans = controller.bans;
    return GuildSettingsPanel(
      title: 'Bans',
      subtitle: 'Banned accounts cannot rejoin until they are unbanned.',
      trailing: FilledButton.tonal(
        key: const ValueKey('guild-ban-open'),
        onPressed: controller.isBusy ? null : () => _openBanDialog(context),
        child: const Text('Ban members'),
      ),
      children: [
        GuildSettingsActionError(error: controller.actionError),
        TextField(
          key: const ValueKey('guild-ban-search'),
          controller: _search,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: 'Search bans',
          ),
          onSubmitted: (value) => unawaited(controller.searchBans(value)),
        ),
        const SizedBox(height: 14),
        if (bans.isEmpty)
          const GuildSettingsEmpty(message: 'Nobody is banned here.')
        else
          for (final ban in bans)
            GuildSettingsRow(
              key: ValueKey('guild-ban-${ban.userId}'),
              leading: const Icon(Icons.person_off_outlined, size: 16),
              title: ban.displayName,
              subtitle: ban.reason ?? 'No reason recorded',
              trailing: TextButton(
                key: ValueKey('guild-unban-${ban.userId}'),
                onPressed: controller.isBusy
                    ? null
                    : () => unawaited(controller.unbanMember(ban.userId)),
                child: const Text('Unban'),
              ),
            ),
      ],
    );
  }

  Future<void> _openBanDialog(BuildContext context) async {
    final controller = widget.controller;
    final candidates = [
      for (final member in widget.workspace.members)
        if (member.spaceIds.contains(widget.spaceId) &&
            controller.capabilities.canBan(member.id))
          member,
    ];
    final request = await showDialog<BanRequest>(
      context: context,
      builder: (_) =>
          GuildBanDialog(candidates: candidates, spaceId: widget.spaceId),
    );
    if (request == null) return;
    await controller.banMembers(request);
  }
}

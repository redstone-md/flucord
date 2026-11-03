import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import 'flucord_button.dart';
import 'guild_settings_audit_section.dart';
import 'guild_settings_automod_section.dart';
import 'guild_settings_channels_section.dart';
import 'guild_settings_controls.dart';
import 'guild_settings_expressions_section.dart';
import 'guild_settings_invites_section.dart';
import 'guild_settings_moderation_section.dart';
import 'guild_settings_overview_section.dart';
import 'guild_settings_roles_section.dart';
import 'guild_settings_webhooks_section.dart';
import 'flucord_dialog.dart';
import 'settings_layout.dart';

/// Discord's server-settings window.
///
/// Only the sections the account may actually use are listed. Discord does the
/// same, and the reason is not tidiness: a moderator who can ban but not manage
/// roles has no business being shown a roles page whose every control the
/// server would refuse, and a page that renders and then fails is
/// indistinguishable from a broken client.
class GuildSettingsDialog extends StatefulWidget {
  const GuildSettingsDialog({
    required this.controller,
    required this.space,
    required this.workspace,
    super.key,
  });

  final GuildSettingsController controller;
  final CommunitySpace space;
  final ChatWorkspace workspace;

  /// The width below which the section list stops being a side rail.
  ///
  /// Flucord is a desktop client but its window is resizable, and the settings
  /// dialog is the widest surface it has. Below this the rail becomes a
  /// scrolling strip so the content column keeps a usable width instead of
  /// squeezing every form field into forty pixels.
  static const compactWidth = 720.0;

  @override
  State<GuildSettingsDialog> createState() => _GuildSettingsDialogState();
}

class _GuildSettingsDialogState extends State<GuildSettingsDialog> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.openSection(_initialSection()));
  }

  GuildSettingsSection _initialSection() {
    final available = widget.controller.availableSections;
    return available.isEmpty ? GuildSettingsSection.overview : available.first;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final sections = controller.availableSections;
      if (sections.isEmpty) return _noPermissionView();
      return SettingsLayout(
        key: const ValueKey('guild-settings-dialog'),
        compactWidth: GuildSettingsDialog.compactWidth,
        closeKey: const ValueKey('guild-settings-close'),
        stripKey: const ValueKey('guild-settings-section-strip'),
        title: widget.space.name,
        busy: controller.isBusy,
        groups: [
          SettingsNavGroup(
            heading: 'Server settings',
            entries: [
              for (final section in sections)
                SettingsNavEntry(
                  key: ValueKey('guild-settings-rail-${section.name}'),
                  compactKey: ValueKey('guild-settings-chip-${section.name}'),
                  label: guildSettingsSectionLabel(section),
                  icon: guildSettingsSectionIcon(section),
                  selected: section == controller.section,
                  onPressed: () => unawaited(controller.openSection(section)),
                ),
            ],
          ),
        ],
        body: _sectionBody(context),
      );
    },
  );

  Widget _sectionBody(BuildContext context) {
    final controller = widget.controller;
    final section = controller.section;
    if (controller.isLoading(section)) {
      return const Center(
        key: ValueKey('guild-settings-loading'),
        child: CircularProgressIndicator(),
      );
    }
    final error = controller.errorFor(section);
    if (error != null) {
      return GuildSettingsRetry(
        message: 'That section could not be loaded.',
        onRetry: () => unawaited(controller.load(section, refresh: true)),
      );
    }
    return switch (section) {
      GuildSettingsSection.overview => GuildSettingsOverviewSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.roles => GuildSettingsRolesSection(
        controller: controller,
      ),
      GuildSettingsSection.channels => GuildSettingsChannelsSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.bans => GuildSettingsModerationSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.automod => GuildSettingsAutoModSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.invites => GuildSettingsInvitesSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.webhooks => GuildSettingsWebhooksSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.expressions => GuildSettingsExpressionsSection(
        controller: controller,
      ),
      GuildSettingsSection.auditLog => GuildSettingsAuditSection(
        controller: controller,
      ),
    };
  }

  /// Nothing to list: a small dialog says so instead of an empty window.
  Widget _noPermissionView() => Builder(
    builder: (context) => FlucordDialog(
      key: const ValueKey('guild-settings-forbidden'),
      title: const Text('You cannot manage this server'),
      description:
          'Your roles here do not include any server settings permission.',
      onConfirm: () => Navigator.of(context).maybePop(),
      actions: [
        FlucordButton(
          kind: FlucordButtonKind.primary,
          label: 'Close',
          keyHint: FlucordKeyHint.enter,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
}

/// The window's own name for each section.
String guildSettingsSectionLabel(GuildSettingsSection section) =>
    switch (section) {
      GuildSettingsSection.overview => 'Overview',
      GuildSettingsSection.roles => 'Roles',
      GuildSettingsSection.channels => 'Channels',
      GuildSettingsSection.bans => 'Bans',
      GuildSettingsSection.automod => 'AutoMod',
      GuildSettingsSection.invites => 'Invites',
      GuildSettingsSection.webhooks => 'Webhooks',
      GuildSettingsSection.expressions => 'Expressions',
      GuildSettingsSection.auditLog => 'Audit Log',
    };

/// The navigation icon for each section.
FlucordIconData guildSettingsSectionIcon(GuildSettingsSection section) =>
    switch (section) {
      GuildSettingsSection.overview => FlucordIcons.overview,
      GuildSettingsSection.roles => FlucordIcons.roles,
      GuildSettingsSection.channels => FlucordIcons.textChannel,
      GuildSettingsSection.bans => FlucordIcons.ban,
      GuildSettingsSection.automod => FlucordIcons.automod,
      GuildSettingsSection.invites => FlucordIcons.invite,
      GuildSettingsSection.webhooks => FlucordIcons.webhooks,
      GuildSettingsSection.expressions => FlucordIcons.expressions,
      GuildSettingsSection.auditLog => FlucordIcons.auditLog,
    };

/// Opens the window for [space].
Future<void> showGuildSettingsDialog({
  required BuildContext context,
  required GuildSettingsController controller,
  required CommunitySpace space,
  required ChatWorkspace workspace,
}) => showDialog<void>(
  context: context,
  builder: (_) => GuildSettingsDialog(
    controller: controller,
    space: space,
    workspace: workspace,
  ),
);

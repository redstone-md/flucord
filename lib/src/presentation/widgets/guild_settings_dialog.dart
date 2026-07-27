import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'guild_settings_audit_section.dart';
import 'guild_settings_channels_section.dart';
import 'guild_settings_controls.dart';
import 'guild_settings_invites_section.dart';
import 'guild_settings_moderation_section.dart';
import 'guild_settings_overview_section.dart';
import 'guild_settings_roles_section.dart';

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
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey('guild-settings-dialog'),
      backgroundColor: context.surfaces.surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 660),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) => _layout(
              context,
              isCompact:
                  constraints.maxWidth < GuildSettingsDialog.compactWidth,
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, {required bool isCompact}) {
    final sections = widget.controller.availableSections;
    if (sections.isEmpty) return _noPermissionView(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context),
        if (isCompact) _sectionStrip(context, sections),
        Flexible(
          child: isCompact
              ? _sectionBody(context)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: _sectionRail(context, sections),
                    ),
                    VerticalDivider(width: 1, color: context.surfaces.border),
                    Expanded(child: _sectionBody(context)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            widget.space.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        if (widget.controller.isBusy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          key: const ValueKey('guild-settings-close'),
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );

  Widget _sectionRail(
    BuildContext context,
    List<GuildSettingsSection> sections,
  ) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    children: [
      for (final section in sections)
        _RailEntry(
          section: section,
          selected: section == widget.controller.section,
          onSelected: () => unawaited(widget.controller.openSection(section)),
        ),
    ],
  );

  Widget _sectionStrip(
    BuildContext context,
    List<GuildSettingsSection> sections,
  ) => SizedBox(
    height: 52,
    child: ListView(
      key: const ValueKey('guild-settings-section-strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: ValueKey('guild-settings-chip-${section.name}'),
              label: Text(guildSettingsSectionLabel(section)),
              selected: section == widget.controller.section,
              onSelected: (_) =>
                  unawaited(widget.controller.openSection(section)),
            ),
          ),
      ],
    ),
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
      GuildSettingsSection.invites => GuildSettingsInvitesSection(
        controller: controller,
        workspace: widget.workspace,
        spaceId: widget.space.id,
      ),
      GuildSettingsSection.auditLog => GuildSettingsAuditSection(
        controller: controller,
      ),
    };
  }

  Widget _noPermissionView(BuildContext context) => Padding(
    key: const ValueKey('guild-settings-forbidden'),
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, size: 32),
        const SizedBox(height: 12),
        const Text('You cannot manage this server.'),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
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
      GuildSettingsSection.invites => 'Invites',
      GuildSettingsSection.auditLog => 'Audit Log',
    };

IconData guildSettingsSectionIcon(GuildSettingsSection section) =>
    switch (section) {
      GuildSettingsSection.overview => Icons.tune,
      GuildSettingsSection.roles => Icons.shield_outlined,
      GuildSettingsSection.channels => Icons.tag,
      GuildSettingsSection.bans => Icons.gavel,
      GuildSettingsSection.invites => Icons.link,
      GuildSettingsSection.auditLog => Icons.receipt_long,
    };

class _RailEntry extends StatelessWidget {
  const _RailEntry({
    required this.section,
    required this.selected,
    required this.onSelected,
  });

  final GuildSettingsSection section;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Material(
      color: selected ? context.surfaces.control : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: ValueKey('guild-settings-rail-${section.name}'),
        borderRadius: BorderRadius.circular(4),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(guildSettingsSectionIcon(section), size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  guildSettingsSectionLabel(section),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

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

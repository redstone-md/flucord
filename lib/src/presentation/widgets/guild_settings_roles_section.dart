import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/discord_permissions.dart';
import '../../domain/guild_management.dart';
import '../../theme/flucord_theme.dart';
import 'guild_settings_controls.dart';

/// The roles page: the list, its order, and one role's editor.
///
/// Order runs highest-first, the way Discord shows it, and the move buttons are
/// offered only for roles the account outranks. Role position is not a
/// permission bit, so a page that gated on `MANAGE_ROLES` alone would let a
/// moderator drag a role above their own and find out from a rejected request.
class GuildSettingsRolesSection extends StatefulWidget {
  const GuildSettingsRolesSection({required this.controller, super.key});

  final GuildSettingsController controller;

  @override
  State<GuildSettingsRolesSection> createState() =>
      _GuildSettingsRolesSectionState();
}

class _GuildSettingsRolesSectionState extends State<GuildSettingsRolesSection> {
  String? _editingRoleId;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final roles = controller.roles;
    final editing = roles
        .where((role) => role.id == _editingRoleId)
        .firstOrNull;
    if (editing != null) {
      return GuildRoleEditor(
        key: ValueKey('guild-role-editor-${editing.id}'),
        controller: controller,
        role: editing,
        onClose: () => setState(() => _editingRoleId = null),
      );
    }
    return GuildSettingsPanel(
      title: 'Roles',
      subtitle: 'Highest first. Members take the colour of their top role.',
      trailing: FilledButton.tonal(
        key: const ValueKey('guild-role-create'),
        onPressed: controller.isBusy ? null : _createRole,
        child: const Text('New role'),
      ),
      children: [
        GuildSettingsActionError(error: controller.actionError),
        if (roles.isEmpty)
          const GuildSettingsEmpty(message: 'This server has no roles yet.')
        else
          for (var index = 0; index < roles.length; index++)
            _roleRow(context, roles, index),
      ],
    );
  }

  Widget _roleRow(BuildContext context, List<GuildRole> roles, int index) {
    final controller = widget.controller;
    final role = roles[index];
    final editable = controller.canEditRole(role);
    return GuildSettingsRow(
      key: ValueKey('guild-role-${role.id}'),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: role.colorValue == 0
              ? context.surfaces.muted
              : Color(0xFF000000 | role.colorValue),
        ),
      ),
      title: role.name,
      subtitle: _describe(role),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('guild-role-up-${role.id}'),
            tooltip: 'Move up',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward),
            onPressed: editable && index > 0 && !controller.isBusy
                ? () => unawaited(controller.moveRole(role, offset: -1))
                : null,
          ),
          IconButton(
            key: ValueKey('guild-role-down-${role.id}'),
            tooltip: 'Move down',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward),
            onPressed:
                editable && index < roles.length - 1 && !controller.isBusy
                ? () => unawaited(controller.moveRole(role, offset: 1))
                : null,
          ),
          IconButton(
            key: ValueKey('guild-role-edit-${role.id}'),
            tooltip: 'Edit role',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined),
            onPressed: editable
                ? () => setState(() => _editingRoleId = role.id)
                : null,
          ),
          IconButton(
            key: ValueKey('guild-role-delete-${role.id}'),
            tooltip: 'Delete role',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline),
            onPressed: controller.canDeleteRole(role) && !controller.isBusy
                ? () => unawaited(controller.deleteRole(role))
                : null,
          ),
        ],
      ),
    );
  }

  String _describe(GuildRole role) {
    if (role.managed) return 'Managed by an integration';
    if (role.isEveryone) return 'Applies to everybody';
    final parts = <String>[
      if (role.hoist) 'Shown separately',
      if (role.mentionable) 'Mentionable',
    ];
    return parts.isEmpty ? 'Position ${role.position}' : parts.join(' - ');
  }

  void _createRole() => unawaited(
    widget.controller.createRole(const GuildRoleDraft(name: 'new role')),
  );
}

/// One role's editor.
class GuildRoleEditor extends StatefulWidget {
  const GuildRoleEditor({
    required this.controller,
    required this.role,
    required this.onClose,
    super.key,
  });

  final GuildSettingsController controller;
  final GuildRole role;
  final VoidCallback onClose;

  /// The permissions the editor offers.
  ///
  /// Not the full 54: Discord's own page groups them behind headings and this
  /// one does not have the room. These are the bits a server actually hands out
  /// and takes back, and every other bit the role holds is left exactly as it
  /// was, because the edit sends the whole bitfield and dropping the ones it
  /// cannot render would silently revoke them.
  static final editable = <(String, BigInt)>[
    ('View channels', DiscordPermissions.viewChannel),
    ('Send messages', DiscordPermissions.sendMessages),
    ('Manage messages', DiscordPermissions.manageMessages),
    ('Attach files', DiscordPermissions.attachFiles),
    ('Mention @everyone', DiscordPermissions.mentionEveryone),
    ('Create invites', DiscordPermissions.createInstantInvite),
    ('Kick members', DiscordPermissions.kickMembers),
    ('Ban members', DiscordPermissions.banMembers),
    ('Time out members', DiscordPermissions.moderateMembers),
    ('Manage channels', DiscordPermissions.manageChannels),
    ('Manage roles', DiscordPermissions.manageRoles),
    ('View audit log', DiscordPermissions.viewAuditLog),
    ('Manage server', DiscordPermissions.manageGuild),
    ('Administrator', DiscordPermissions.administrator),
  ];

  @override
  State<GuildRoleEditor> createState() => _GuildRoleEditorState();
}

class _GuildRoleEditorState extends State<GuildRoleEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.role.name,
  );
  late bool _hoist = widget.role.hoist;
  late bool _mentionable = widget.role.mentionable;
  late BigInt _permissions = widget.role.permissions;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GuildSettingsPanel(
    title: 'Edit ${widget.role.name}',
    trailing: TextButton(
      key: const ValueKey('guild-role-editor-back'),
      onPressed: widget.onClose,
      child: const Text('Back'),
    ),
    children: [
      GuildSettingsActionError(error: widget.controller.actionError),
      GuildSettingsField(
        label: 'Role name',
        child: TextField(
          key: const ValueKey('guild-role-name'),
          controller: _name,
          enabled: !widget.role.isEveryone,
          decoration: const InputDecoration(isDense: true),
        ),
      ),
      SwitchListTile(
        key: const ValueKey('guild-role-hoist'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Show members separately in the sidebar'),
        value: _hoist,
        onChanged: widget.role.isEveryone
            ? null
            : (value) => setState(() => _hoist = value),
      ),
      SwitchListTile(
        key: const ValueKey('guild-role-mentionable'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow anyone to @mention this role'),
        value: _mentionable,
        onChanged: widget.role.isEveryone
            ? null
            : (value) => setState(() => _mentionable = value),
      ),
      const Divider(height: 24),
      for (final (label, bit) in GuildRoleEditor.editable)
        SwitchListTile(
          key: ValueKey('guild-role-permission-$label'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label),
          value: DiscordPermissions.hasAll(_permissions, bit),
          // A permission the account does not hold cannot be handed out, so
          // the switch is shown in its current state but locked.
          onChanged: !widget.controller.capabilities.canGrant(bit)
              ? null
              : (value) => setState(() {
                  _permissions = value
                      ? DiscordPermissions.add(_permissions, bit)
                      : DiscordPermissions.remove(_permissions, bit);
                }),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          key: const ValueKey('guild-role-save'),
          onPressed: widget.controller.isBusy ? null : _save,
          child: const Text('Save role'),
        ),
      ),
    ],
  );

  void _save() {
    final edit = GuildRoleEdit();
    final name = _name.text.trim();
    if (!widget.role.isEveryone) {
      if (name.isNotEmpty && name != widget.role.name) edit.name = name;
      if (_hoist != widget.role.hoist) edit.hoist = _hoist;
      if (_mentionable != widget.role.mentionable) {
        edit.mentionable = _mentionable;
      }
    }
    if (_permissions != widget.role.permissions) {
      edit.permissions = _permissions;
    }
    unawaited(
      widget.controller.saveRole(widget.role, edit).then((saved) {
        if (saved && mounted) widget.onClose();
      }),
    );
  }
}

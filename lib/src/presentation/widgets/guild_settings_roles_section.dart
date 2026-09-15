import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/discord_permissions.dart';
import '../../domain/guild_management.dart';
import '../../theme/flucord_theme.dart';
import '../profile_image_picker.dart';
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
    this.imagePicker = const NativeProfileImagePicker(),
    super.key,
  });

  final GuildSettingsController controller;
  final GuildRole role;
  final VoidCallback onClose;

  /// Chooses the role icon. Injected so a test can answer without a file
  /// dialog, and shared with the profile pages rather than picked twice.
  final ProfileImagePicker imagePicker;

  /// Every named permission bit, in wire order, with the label the switch
  /// carries.
  ///
  /// Generated from the constants themselves so the grid can never fall
  /// behind them: a bit Discord adds lands here through the constant, and a
  /// bit this build cannot name is the one bit deliberately absent from the
  /// set. The editor sends the whole bitfield, so a role's unlisted bits were
  /// once silently kept rather than revoked; now there are no unlisted bits.
  static final editable = <(String, BigInt)>[
    ('Create invites', DiscordPermissions.createInstantInvite),
    ('Kick members', DiscordPermissions.kickMembers),
    ('Ban members', DiscordPermissions.banMembers),
    ('Administrator', DiscordPermissions.administrator),
    ('Manage channels', DiscordPermissions.manageChannels),
    ('Manage server', DiscordPermissions.manageGuild),
    ('Add reactions', DiscordPermissions.addReactions),
    ('View audit log', DiscordPermissions.viewAuditLog),
    ('Priority speaker', DiscordPermissions.prioritySpeaker),
    ('Stream', DiscordPermissions.stream),
    ('View channels', DiscordPermissions.viewChannel),
    ('Send messages', DiscordPermissions.sendMessages),
    ('Send text-to-speech messages', DiscordPermissions.sendTtsMessages),
    ('Manage messages', DiscordPermissions.manageMessages),
    ('Embed links', DiscordPermissions.embedLinks),
    ('Attach files', DiscordPermissions.attachFiles),
    ('Read message history', DiscordPermissions.readMessageHistory),
    ('Mention @everyone', DiscordPermissions.mentionEveryone),
    ('Use external emoji', DiscordPermissions.useExternalEmojis),
    ('View server insights', DiscordPermissions.viewGuildAnalytics),
    ('Connect', DiscordPermissions.connect),
    ('Speak', DiscordPermissions.speak),
    ('Mute members', DiscordPermissions.muteMembers),
    ('Deafen members', DiscordPermissions.deafenMembers),
    ('Move members', DiscordPermissions.moveMembers),
    ('Use voice activity', DiscordPermissions.useVoiceActivity),
    ('Change own nickname', DiscordPermissions.changeNickname),
    ('Manage nicknames', DiscordPermissions.manageNicknames),
    ('Manage roles', DiscordPermissions.manageRoles),
    ('Manage webhooks', DiscordPermissions.manageWebhooks),
    ('Manage emoji and stickers', DiscordPermissions.manageGuildExpressions),
    ('Use application commands', DiscordPermissions.useApplicationCommands),
    ('Request to speak', DiscordPermissions.requestToSpeak),
    ('Manage events', DiscordPermissions.manageEvents),
    ('Manage threads', DiscordPermissions.manageThreads),
    ('Create public threads', DiscordPermissions.createPublicThreads),
    ('Create private threads', DiscordPermissions.createPrivateThreads),
    ('Use external stickers', DiscordPermissions.useExternalStickers),
    ('Send messages in threads', DiscordPermissions.sendMessagesInThreads),
    ('Use embedded activities', DiscordPermissions.useEmbeddedActivities),
    ('Time out members', DiscordPermissions.moderateMembers),
    (
      'View creator monetization analytics',
      DiscordPermissions.viewCreatorMonetizationAnalytics,
    ),
    ('Use the soundboard', DiscordPermissions.useSoundboard),
    ('Create emoji and stickers', DiscordPermissions.createGuildExpressions),
    ('Create events', DiscordPermissions.createEvents),
    ('Use external sounds', DiscordPermissions.useExternalSounds),
    ('Send voice messages', DiscordPermissions.sendVoiceMessages),
    ('Set room status', DiscordPermissions.setVoiceChannelStatus),
    ('Send polls', DiscordPermissions.sendPolls),
    ('Use external apps', DiscordPermissions.useExternalApps),
    ('Pin messages', DiscordPermissions.pinMessages),
    ('Bypass slowmode', DiscordPermissions.bypassSlowmode),
    ('Manage official messages', DiscordPermissions.manageOfficialMessages),
  ];

  /// The swatches Discord's own colour picker opens with.
  static const _swatches = <int>[
    0x99AAB5,
    0x1ABC9C,
    0x2ECC71,
    0x3498DB,
    0x9B59B6,
    0xE91E63,
    0xF1C40F,
    0xE67E22,
    0xE74C3C,
    0x95A5A6,
    0x607D8B,
    0x11806A,
  ];

  @override
  State<GuildRoleEditor> createState() => _GuildRoleEditorState();
}

class _GuildRoleEditorState extends State<GuildRoleEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.role.name,
  );
  final TextEditingController _hex = TextEditingController();

  late bool _hoist = widget.role.hoist;
  late bool _mentionable = widget.role.mentionable;
  late BigInt _permissions = widget.role.permissions;

  /// The colour this sitting has settled on, or `null` while untouched.
  ///
  /// Absent is not "default": the send has to tell Discord whether the role
  /// keeps its colour, takes a new one, or drops back to default, and only a
  /// null can stand for the first.
  int? _colorValue;
  bool _hexEdited = false;

  /// The icon as chosen in this sitting, and whether it was cleared. Same
  /// tri-state reasoning as the colour.
  String? _icon;
  bool _iconCleared = false;

  @override
  void initState() {
    super.initState();
    _hex.text = widget.role.colorValue == 0
        ? ''
        : widget.role.colorValue
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase();
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
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
      GuildSettingsField(
        label: 'Role colour',
        hint: 'Members take the colour of their top role.',
        child: _colorPicker,
      ),
      GuildSettingsField(
        label: 'Role icon',
        hint: _iconLabel,
        child: Row(
          children: [
            FilledButton.tonal(
              key: const ValueKey('guild-role-icon-pick'),
              onPressed: widget.controller.isBusy ? null : _pickIcon,
              child: const Text('Choose image'),
            ),
            if (_icon != null || (_hasExistingIcon && !_iconCleared)) ...[
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('guild-role-icon-clear'),
                tooltip: 'Remove icon',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _icon = null;
                  _iconCleared = true;
                }),
              ),
            ],
          ],
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

  bool get _hasExistingIcon => widget.role.iconHash != null;

  String get _iconLabel {
    if (_icon != null) return 'A new icon will be sent.';
    if (_iconCleared) return 'The icon will be removed.';
    return _hasExistingIcon ? 'An icon is set.' : 'No icon yet.';
  }

  /// The colour the swatches should mark as selected.
  int get _selectedColor => _colorValue ?? widget.role.colorValue;

  Widget get _colorPicker => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final swatch in GuildRoleEditor._swatches)
            _ColorSwatch(
              key: ValueKey('guild-role-colour-$swatch'),
              colorValue: swatch,
              selected: _selectedColor == swatch,
              onPressed: () => _applyColor(swatch),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('guild-role-colour-hex'),
              controller: _hex,
              enabled: !widget.role.isEveryone,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'RRGGBB',
              ),
              onChanged: (_) => setState(() {
                _hexEdited = true;
                _colorValue = _hexToColor(_hex.text) ?? _colorValue;
              }),
            ),
          ),
          const SizedBox(width: 8),
          _ColorSwatch(
            key: const ValueKey('guild-role-colour-default'),
            colorValue: 0,
            selected: _selectedColor == 0,
            onPressed: () => _applyColor(0),
          ),
        ],
      ),
    ],
  );

  /// A swatch click is a whole answer: the hex field follows it.
  void _applyColor(int value) {
    setState(() {
      _colorValue = value;
      _hexEdited = false;
      _hex.text = value == 0
          ? ''
          : value.toRadixString(16).padLeft(6, '0').toUpperCase();
    });
  }

  /// Reads the hex field. A blank field means default, matching the swatch
  /// beside it; anything unreadable is left for the field to show as typed.
  static int? _hexToColor(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    final digits = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (digits.length != 6) return null;
    final value = int.tryParse(digits, radix: 16);
    if (value == null || value < 0) return null;
    return value;
  }

  Future<void> _pickIcon() async {
    final selection = await widget.imagePicker.pick();
    if (selection == null || !mounted) return;
    setState(() {
      _icon = selection.dataUri;
      _iconCleared = false;
    });
  }

  void _save() {
    final edit = GuildRoleEdit();
    final name = _name.text.trim();
    if (!widget.role.isEveryone) {
      if (name.isNotEmpty && name != widget.role.name) edit.name = name;
      if (_hoist != widget.role.hoist) edit.hoist = _hoist;
      if (_mentionable != widget.role.mentionable) {
        edit.mentionable = _mentionable;
      }
      final color = _hexToColor(_hex.text);
      // A swatch click is a whole answer; typed hex wins while it stays
      // readable, and the last readable value stands when it does not.
      final chosen = _hexEdited ? (color ?? _colorValue) : _colorValue;
      if (chosen != null && chosen != widget.role.colorValue) {
        edit.colorValue = chosen;
      }
      // Absent means untouched; cleared means take the icon off. Collapsing
      // the two would drop somebody's icon every time they renamed a role.
      if (_icon != null) {
        edit.icon = _icon;
      } else if (_iconCleared && _hasExistingIcon) {
        edit.icon = null;
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

/// One swatch of the colour picker, plus the default-state one.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.colorValue,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = colorValue == 0
        ? context.surfaces.muted
        : Color(0xFF000000 | colorValue);
    return Semantics(
      button: true,
      label: colorValue == 0 ? 'Default colour' : '#${_hexLabel(colorValue)}',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : context.surfaces.border,
              width: selected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }

  static String _hexLabel(int value) =>
      value.toRadixString(16).padLeft(6, '0').toUpperCase();
}

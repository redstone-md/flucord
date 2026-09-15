import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/discord_permissions.dart';
import '../../domain/guild_management.dart';
import '../../domain/permission_overwrite.dart';
import '../../theme/flucord_theme.dart';
import 'guild_settings_controls.dart';

/// The channels page: create, rename, reorder, delete.
///
/// The list it works from is the workspace's, not a fresh fetch — the sidebar
/// already holds every channel the account can see, kept current by the
/// gateway, and asking again would show a different list from the one behind
/// the dialog.
class GuildSettingsChannelsSection extends StatefulWidget {
  const GuildSettingsChannelsSection({
    required this.controller,
    required this.workspace,
    required this.spaceId,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final String spaceId;

  @override
  State<GuildSettingsChannelsSection> createState() =>
      _GuildSettingsChannelsSectionState();
}

class _GuildSettingsChannelsSectionState
    extends State<GuildSettingsChannelsSection> {
  String? _editingChannelId;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final channels = _channels();
    final editing = channels
        .where((channel) => channel.id == _editingChannelId)
        .firstOrNull;
    if (editing != null) {
      return _ChannelEditor(
        key: ValueKey('guild-channel-editor-${editing.id}'),
        controller: controller,
        workspace: widget.workspace,
        channel: editing,
        onClose: () => setState(() => _editingChannelId = null),
      );
    }
    return GuildSettingsPanel(
      title: 'Channels',
      subtitle: 'Order here is the order in the sidebar.',
      trailing: FilledButton.tonal(
        key: const ValueKey('guild-channel-create'),
        onPressed: controller.isBusy ? null : () => _create(context),
        child: const Text('New channel'),
      ),
      children: [
        GuildSettingsActionError(error: controller.actionError),
        if (channels.isEmpty)
          const GuildSettingsEmpty(message: 'No channels to manage.')
        else
          for (var index = 0; index < channels.length; index++)
            _channelRow(channels, index),
      ],
    );
  }

  List<ConversationChannel> _channels() =>
      widget.workspace
          .channelsFor(widget.spaceId)
          .where((channel) => !channel.isThread)
          .toList(growable: false)
        ..sort((left, right) {
          if (left.position != right.position) {
            return left.position.compareTo(right.position);
          }
          return left.id.compareTo(right.id);
        });

  Widget _channelRow(List<ConversationChannel> channels, int index) {
    final controller = widget.controller;
    final channel = channels[index];
    final manageable = controller.capabilities.canManageChannels;
    return GuildSettingsRow(
      key: ValueKey('guild-channel-${channel.id}'),
      leading: Icon(_iconFor(channel.kind), size: 16),
      title: channel.name,
      subtitle: channel.topic.isEmpty ? null : channel.topic,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('guild-channel-up-${channel.id}'),
            tooltip: 'Move up',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_upward),
            onPressed: manageable && index > 0 && !controller.isBusy
                ? () => _move(channels, index, -1)
                : null,
          ),
          IconButton(
            key: ValueKey('guild-channel-down-${channel.id}'),
            tooltip: 'Move down',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_downward),
            onPressed:
                manageable && index < channels.length - 1 && !controller.isBusy
                ? () => _move(channels, index, 1)
                : null,
          ),
          IconButton(
            key: ValueKey('guild-channel-edit-${channel.id}'),
            tooltip: 'Edit channel',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined),
            onPressed: manageable
                ? () => setState(() => _editingChannelId = channel.id)
                : null,
          ),
          IconButton(
            key: ValueKey('guild-channel-delete-${channel.id}'),
            tooltip: 'Delete channel',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline),
            onPressed: manageable && !controller.isBusy
                ? () => unawaited(controller.deleteChannel(channel.id))
                : null,
          ),
        ],
      ),
    );
  }

  /// Swaps two rows and sends the whole reorder as one batch.
  ///
  /// Both orderings go to the delta pass so it can drop the channels that did
  /// not really move. A "swap these two" request would be smaller and wrong:
  /// Discord's positions are not list indices, and a guild whose channels all
  /// carry position 0 needs every row renumbered.
  void _move(List<ConversationChannel> channels, int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= channels.length) return;
    final before = [for (final channel in channels) _entryOf(channel)];
    final reordered = [...channels];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);
    unawaited(
      widget.controller.reorderChannels(
        before: before,
        after: [for (final channel in reordered) _entryOf(channel)],
      ),
    );
  }

  static ChannelOrderEntry _entryOf(ConversationChannel channel) =>
      ChannelOrderEntry(
        id: channel.id,
        position: channel.position,
        type: switch (channel.kind) {
          ChannelKind.voice => GuildChannelType.voice,
          ChannelKind.forum || ChannelKind.media => GuildChannelType.forum,
          ChannelKind.text => GuildChannelType.text,
        },
        parentId: channel.parentId,
      );

  static IconData _iconFor(ChannelKind kind) => switch (kind) {
    ChannelKind.voice => Icons.volume_up,
    ChannelKind.forum => Icons.forum_outlined,
    ChannelKind.media => Icons.perm_media_outlined,
    ChannelKind.text => Icons.tag,
  };

  Future<void> _create(BuildContext context) async {
    final draft = await showDialog<GuildChannelDraft>(
      context: context,
      builder: (_) => _CreateChannelDialog(
        categories: _channels()
            .where((channel) => channel.parentId == null)
            .toList(growable: false),
      ),
    );
    if (draft == null) return;
    await widget.controller.createChannel(draft);
  }
}

class _ChannelEditor extends StatefulWidget {
  const _ChannelEditor({
    required this.controller,
    required this.workspace,
    required this.channel,
    required this.onClose,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final VoidCallback onClose;

  @override
  State<_ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<_ChannelEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.channel.name,
  );
  late final TextEditingController _topic = TextEditingController(
    text: widget.channel.topic,
  );

  /// The editor's working state. The channel's current values seed it, and
  /// only what differs from them is sent.
  late int _slowmode = widget.channel.rateLimitPerUser;
  late bool _ageGated = widget.channel.isAgeGated;
  late int _bitrate = widget.channel.bitrate ?? _defaultBitrate;
  late int _userLimit = widget.channel.userLimit ?? 0;
  late String? _parent = widget.channel.parentId;
  late String? _region = widget.channel.rtcRegion;

  /// Overwrites held by id, so an edit to one entry cannot fork another. The
  /// channel's own map seeds it, and the whole list replaces the channel's on
  /// save: Discord's route takes the array, not a delta.
  late final Map<String, DiscordPermissionOverwrite> _overwrites = {
    for (final entry in widget.channel.permissionOverwrites.entries)
      entry.key: entry.value,
  };
  bool _overwritesDirty = false;

  static const _defaultBitrate = 64000;

  /// The slowmode ladder Discord's own editor offers, seconds first.
  static const _slowmodeChoices = <(int, String)>[
    (0, 'Off'),
    (5, '5 seconds'),
    (10, '10 seconds'),
    (15, '15 seconds'),
    (30, '30 seconds'),
    (60, '1 minute'),
    (120, '2 minutes'),
    (300, '5 minutes'),
    (600, '10 minutes'),
    (900, '15 minutes'),
    (1800, '30 minutes'),
    (3600, '1 hour'),
    (7200, '2 hours'),
    (21600, '6 hours'),
  ];

  static const _bitrateChoices = <(int, String)>[
    (8000, '8 kbps'),
    (16000, '16 kbps'),
    (24000, '24 kbps'),
    (32000, '32 kbps'),
    (48000, '48 kbps'),
    (64000, '64 kbps'),
    (96000, '96 kbps'),
    (128000, '128 kbps'),
    (256000, '256 kbps'),
    (384000, '384 kbps'),
  ];

  static const _userLimitChoices = <int>[0, 5, 10, 25, 50, 100, 200];

  bool get _isVoice => widget.channel.kind == ChannelKind.voice;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    return GuildSettingsPanel(
      title: 'Edit ${channel.name}',
      trailing: TextButton(
        key: const ValueKey('guild-channel-editor-back'),
        onPressed: widget.onClose,
        child: const Text('Back'),
      ),
      children: [
        GuildSettingsActionError(error: widget.controller.actionError),
        GuildSettingsField(
          label: 'Channel name',
          child: TextField(
            key: const ValueKey('guild-channel-name'),
            controller: _name,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        GuildSettingsField(
          label: 'Topic',
          child: TextField(
            key: const ValueKey('guild-channel-topic'),
            controller: _topic,
            maxLines: 2,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        GuildSettingsField(
          label: 'Age gate',
          hint:
              'Hides this channel from members who have not agreed to '
              'age-restricted content.',
          child: SwitchListTile(
            key: const ValueKey('guild-channel-age-gate'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Age-restricted channel'),
            value: _ageGated,
            onChanged: (value) => setState(() => _ageGated = value),
          ),
        ),
        GuildSettingsField(
          label: 'Slowmode',
          hint: 'How long a member waits between messages.',
          child: DropdownButtonFormField<int>(
            key: const ValueKey('guild-channel-slowmode'),
            initialValue: _slowmode,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final (seconds, label) in _slowmodeChoices)
                DropdownMenuItem(value: seconds, child: Text(label)),
            ],
            onChanged: (value) => setState(() => _slowmode = value ?? 0),
          ),
        ),
        GuildSettingsField(
          label: 'Parent category',
          hint: 'Where this channel sits in the sidebar.',
          child: DropdownButtonFormField<String?>(
            key: const ValueKey('guild-channel-parent'),
            initialValue: _parent,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No category'),
              ),
              for (final category in _categories())
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: (value) => setState(() => _parent = value),
          ),
        ),
        if (_isVoice) ...[
          GuildSettingsField(
            label: 'Bitrate',
            child: DropdownButtonFormField<int>(
              key: const ValueKey('guild-channel-bitrate'),
              initialValue: _bitrate,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final (bits, label) in _bitrateChoices)
                  DropdownMenuItem(value: bits, child: Text(label)),
              ],
              onChanged: (value) =>
                  setState(() => _bitrate = value ?? _bitrate),
            ),
          ),
          GuildSettingsField(
            label: 'User limit',
            hint: 'Zero means no limit.',
            child: DropdownButtonFormField<int>(
              key: const ValueKey('guild-channel-user-limit'),
              initialValue: _userLimit,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final limit in _userLimitChoices)
                  DropdownMenuItem(
                    value: limit,
                    child: Text(limit == 0 ? 'No limit' : '$limit'),
                  ),
              ],
              onChanged: (value) => setState(() => _userLimit = value ?? 0),
            ),
          ),
          GuildSettingsField(
            label: 'Voice region override',
            hint: 'Where the room lives. Auto picks the nearest region.',
            child: DropdownButtonFormField<String?>(
              key: const ValueKey('guild-channel-region'),
              initialValue: _region,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Auto'),
                ),
                for (final region in regionChoices)
                  DropdownMenuItem(value: region, child: Text(region)),
              ],
              onChanged: (value) => setState(() => _region = value),
            ),
          ),
        ],
        const Divider(height: 24),
        _OverwriteEditor(
          overwrites: _overwrites,
          roles: _roleChoices(),
          members: _memberChoices(),
          onChanged: _markOverwritesDirty,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('guild-channel-save'),
            onPressed: widget.controller.isBusy ? null : _save,
            child: const Text('Save channel'),
          ),
        ),
      ],
    );
  }

  List<ChannelCategory> _categories() =>
      widget.workspace
          .categoriesFor(widget.channel.spaceId)
          .toList(growable: false)
        ..sort((left, right) {
          if (left.position != right.position) {
            return left.position.compareTo(right.position);
          }
          return left.id.compareTo(right.id);
        });

  List<CommunityRole> _roleChoices() =>
      widget.workspace.roles
          .where((role) => role.spaceId == widget.channel.spaceId)
          .toList(growable: false)
        ..sort((left, right) {
          if (left.position != right.position) {
            return right.position.compareTo(left.position);
          }
          return left.id.compareTo(right.id);
        });

  List<Member> _memberChoices() =>
      widget.workspace.members
          .where((member) => member.spaceIds.contains(widget.channel.spaceId))
          .toList(growable: false)
        ..sort((left, right) => left.displayName.compareTo(right.displayName));

  void _markOverwritesDirty() {
    if (!_overwritesDirty) setState(() => _overwritesDirty = true);
  }

  void _save() {
    final channel = widget.channel;
    final edit = GuildChannelEdit();
    final name = _name.text.trim();
    if (name.isNotEmpty && name != channel.name) edit.name = name;
    final topic = _topic.text.trim();
    if (topic != channel.topic) {
      edit.topic = topic.isEmpty ? null : topic;
    }
    if (_ageGated != channel.isAgeGated) edit.nsfw = _ageGated;
    if (_slowmode != channel.rateLimitPerUser) {
      edit.rateLimitPerUser = _slowmode;
    }
    if (_parent != channel.parentId) edit.parentId = _parent;
    if (_isVoice) {
      if (_bitrate != (channel.bitrate ?? _defaultBitrate)) {
        edit.bitrate = _bitrate;
      }
      if (_userLimit != (channel.userLimit ?? 0)) {
        edit.userLimit = _userLimit;
      }
      if (_region != channel.rtcRegion) edit.rtcRegion = _region;
    }
    if (_overwritesDirty) {
      edit.permissionOverwrites = _overwrites.values;
    }
    unawaited(
      widget.controller.saveChannel(channelId: channel.id, edit: edit).then((
        saved,
      ) {
        if (saved && mounted) widget.onClose();
      }),
    );
  }
}

/// The region ids Discord's own editor offers, alphabetical. Auto is the
/// null choice and sits first in its own dropdown entry; it is not a member
/// of this list because it is not a region.
const regionChoices = <String>[
  'brazil',
  'dubai',
  'eu-central',
  'europe',
  'hongkong',
  'india',
  'japan',
  'rotterdam',
  'russia',
  'singapore',
  'southafrica',
  'south-korea',
  'sydney',
  'us-east',
  'us-south',
  'us-west',
];

/// One channel's permission overwrites, added and edited in place.
///
/// An overwrite is a triple: who it names, what it grants, what it denies.
/// The who is fixed once chosen (Discord keys overwrites by id, and "change
/// who this row names" is delete-then-add, not an edit), and the grant and
/// deny are independent masks a role may hold both of for different bits.
class _OverwriteEditor extends StatelessWidget {
  const _OverwriteEditor({
    required this.overwrites,
    required this.roles,
    required this.members,
    required this.onChanged,
  });

  final Map<String, DiscordPermissionOverwrite> overwrites;
  final List<CommunityRole> roles;
  final List<Member> members;
  final VoidCallback onChanged;

  /// The bits the overwrite editor offers. Not the full 54: an overwrite is a
  /// channel-shaped answer, and the bits that name guild-wide powers cannot
  /// be meaningfully granted inside one channel.
  static final _editableBits = <(String, BigInt)>[
    ('View channel', DiscordPermissions.viewChannel),
    ('Send messages', DiscordPermissions.sendMessages),
    ('Send text-to-speech', DiscordPermissions.sendTtsMessages),
    ('Manage messages', DiscordPermissions.manageMessages),
    ('Embed links', DiscordPermissions.embedLinks),
    ('Attach files', DiscordPermissions.attachFiles),
    ('Read message history', DiscordPermissions.readMessageHistory),
    ('Mention @everyone', DiscordPermissions.mentionEveryone),
    ('Add reactions', DiscordPermissions.addReactions),
    ('Connect', DiscordPermissions.connect),
    ('Speak', DiscordPermissions.speak),
    ('Mute members', DiscordPermissions.muteMembers),
    ('Deafen members', DiscordPermissions.deafenMembers),
    ('Move members', DiscordPermissions.moveMembers),
    ('Use voice activity', DiscordPermissions.useVoiceActivity),
    ('Priority speaker', DiscordPermissions.prioritySpeaker),
    ('Create invites', DiscordPermissions.createInstantInvite),
    ('Manage webhooks', DiscordPermissions.manageWebhooks),
    ('Manage channels', DiscordPermissions.manageChannels),
    ('Create public threads', DiscordPermissions.createPublicThreads),
    ('Create private threads', DiscordPermissions.createPrivateThreads),
    ('Manage threads', DiscordPermissions.manageThreads),
  ];

  void _add({required String id, required PermissionOverwriteKind kind}) {
    overwrites[id] = DiscordPermissionOverwrite(
      id: id,
      allow: BigInt.zero,
      deny: BigInt.zero,
      kind: kind,
    );
    onChanged();
  }

  void _remove(String id) {
    overwrites.remove(id);
    onChanged();
  }

  void _flip(
    DiscordPermissionOverwrite overwrite, {
    required BigInt bit,
    required bool allow,
  }) {
    overwrites[overwrite.id] = DiscordPermissionOverwrite(
      id: overwrite.id,
      allow: allow
          ? DiscordPermissions.add(overwrite.allow, bit)
          : DiscordPermissions.remove(overwrite.allow, bit),
      deny: allow
          ? DiscordPermissions.remove(overwrite.deny, bit)
          : DiscordPermissions.add(overwrite.deny, bit),
      kind: overwrite.kind,
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final entries = overwrites.values.toList(growable: false)
      ..sort((left, right) {
        final kind = left.kind.index.compareTo(right.kind.index);
        if (kind != 0) return kind;
        return left.id.compareTo(right.id);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERMISSION OVERRIDES',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
            color: context.surfaces.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Private channels are made by denying View channel to @everyone '
          'and granting it to the roles and members who belong.',
          style: TextStyle(fontSize: 11, color: context.surfaces.muted),
        ),
        const SizedBox(height: 10),
        for (final overwrite in entries)
          GuildSettingsRow(
            key: ValueKey('guild-overwrite-${overwrite.id}'),
            leading: Icon(
              overwrite.kind == PermissionOverwriteKind.member
                  ? Icons.person_outline
                  : Icons.group_outlined,
              size: 16,
            ),
            title: _nameOf(overwrite),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  key: ValueKey('guild-overwrite-edit-${overwrite.id}'),
                  onPressed: () => _showBits(context, overwrite),
                  child: const Text('Edit'),
                ),
                TextButton(
                  key: ValueKey('guild-overwrite-delete-${overwrite.id}'),
                  onPressed: () => _remove(overwrite.id),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              key: const ValueKey('guild-overwrite-add-role'),
              onPressed: roles.isEmpty ? null : () => _pickRole(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add role overwrite'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              key: const ValueKey('guild-overwrite-add-member'),
              onPressed: members.isEmpty ? null : () => _pickMember(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add member overwrite'),
            ),
          ],
        ),
      ],
    );
  }

  String _nameOf(DiscordPermissionOverwrite overwrite) {
    if (overwrite.kind == PermissionOverwriteKind.member) {
      return members
              .where((member) => member.id == overwrite.id)
              .firstOrNull
              ?.displayName ??
          'Unknown member';
    }
    return roles.where((role) => role.id == overwrite.id).firstOrNull?.name ??
        'Unknown role';
  }

  Future<void> _pickRole(BuildContext context) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _OverwriteTargetDialog(
        title: 'Add role overwrite',
        entries: [
          for (final role in roles)
            if (!overwrites.containsKey(role.id))
              (id: role.id, label: role.name),
        ],
      ),
    );
    if (id == null) return;
    _add(id: id, kind: PermissionOverwriteKind.role);
  }

  Future<void> _pickMember(BuildContext context) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _OverwriteTargetDialog(
        title: 'Add member overwrite',
        entries: [
          for (final member in members)
            if (!overwrites.containsKey(member.id))
              (id: member.id, label: member.displayName),
        ],
      ),
    );
    if (id == null) return;
    _add(id: id, kind: PermissionOverwriteKind.member);
  }

  Future<void> _showBits(
    BuildContext context,
    DiscordPermissionOverwrite overwrite,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => _OverwriteBitsDialog(
      overwrite: overwrite,
      onFlip: (bit, allow) => _flip(overwrite, bit: bit, allow: allow),
    ),
  );
}

/// Chooses who a new overwrite names.
class _OverwriteTargetDialog extends StatelessWidget {
  const _OverwriteTargetDialog({required this.title, required this.entries});

  final String title;
  final List<({String id, String label})> entries;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: Text(title),
    children: [
      for (final (id: id, label: label) in entries)
        SimpleDialogOption(
          key: ValueKey('overwrite-target-$id'),
          onPressed: () => Navigator.of(context).pop(id),
          child: Text(label),
        ),
    ],
  );
}

/// Edits one overwrite's allow and deny masks, bit by bit.
class _OverwriteBitsDialog extends StatelessWidget {
  const _OverwriteBitsDialog({required this.overwrite, required this.onFlip});

  final DiscordPermissionOverwrite overwrite;
  final void Function(BigInt bit, bool allow) onFlip;

  @override
  Widget build(BuildContext context) {
    final name = overwrite.kind == PermissionOverwriteKind.member
        ? 'member'
        : 'role';
    return AlertDialog(
      key: const ValueKey('overwrite-bits-dialog'),
      title: Text('Overwrite for this $name'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, bit) in _OverwriteEditor._editableBits)
                _bitRow(context, label, bit),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('overwrite-bits-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _bitRow(BuildContext context, String label, BigInt bit) {
    final allows = overwrite.grants(bit);
    final denies = overwrite.denies(bit);
    return Row(
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        TextButton(
          key: ValueKey('overwrite-allow-$label'),
          style: TextButton.styleFrom(
            foregroundColor: allows
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => onFlip(bit, true),
          child: Text(allows ? 'Allowed' : 'Allow'),
        ),
        TextButton(
          key: ValueKey('overwrite-deny-$label'),
          style: TextButton.styleFrom(
            foregroundColor: denies
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => onFlip(bit, false),
          child: Text(denies ? 'Denied' : 'Deny'),
        ),
      ],
    );
  }
}

class _CreateChannelDialog extends StatefulWidget {
  const _CreateChannelDialog({required this.categories});

  final List<ConversationChannel> categories;

  @override
  State<_CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<_CreateChannelDialog> {
  final TextEditingController _name = TextEditingController();
  GuildChannelType _type = GuildChannelType.text;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('create-channel-dialog'),
    title: const Text('Create channel'),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('create-channel-name'),
            controller: _name,
            autofocus: true,
            // The confirm button is gated on a non-blank name, so the field has
            // to drive a rebuild or the button never enables.
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Channel name',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GuildChannelType>(
            key: const ValueKey('create-channel-type'),
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: const [
              DropdownMenuItem(
                value: GuildChannelType.text,
                child: Text('Text channel'),
              ),
              DropdownMenuItem(
                value: GuildChannelType.voice,
                child: Text('Voice channel'),
              ),
              DropdownMenuItem(
                value: GuildChannelType.forum,
                child: Text('Forum channel'),
              ),
              DropdownMenuItem(
                value: GuildChannelType.category,
                child: Text('Category'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _type = value ?? GuildChannelType.text),
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
        key: const ValueKey('create-channel-confirm'),
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.of(
                context,
              ).pop(GuildChannelDraft(type: _type, name: _name.text.trim())),
        child: const Text('Create'),
      ),
    ],
  );
}

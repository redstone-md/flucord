import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
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
    required this.channel,
    required this.onClose,
    super.key,
  });

  final GuildSettingsController controller;
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
  int _slowmode = 0;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GuildSettingsPanel(
    title: 'Edit ${widget.channel.name}',
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
        label: 'Slowmode',
        hint: 'How long a member waits between messages.',
        child: DropdownButtonFormField<int>(
          key: const ValueKey('guild-channel-slowmode'),
          initialValue: _slowmode,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Off')),
            DropdownMenuItem(value: 5, child: Text('5 seconds')),
            DropdownMenuItem(value: 30, child: Text('30 seconds')),
            DropdownMenuItem(value: 300, child: Text('5 minutes')),
            DropdownMenuItem(value: 3600, child: Text('1 hour')),
            DropdownMenuItem(value: 21600, child: Text('6 hours')),
          ],
          onChanged: (value) => setState(() => _slowmode = value ?? 0),
        ),
      ),
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

  void _save() {
    final edit = GuildChannelEdit();
    final name = _name.text.trim();
    if (name.isNotEmpty && name != widget.channel.name) edit.name = name;
    final topic = _topic.text.trim();
    if (topic != widget.channel.topic) {
      edit.topic = topic.isEmpty ? null : topic;
    }
    if (_slowmode > 0) edit.rateLimitPerUser = _slowmode;
    unawaited(
      widget.controller
          .saveChannel(channelId: widget.channel.id, edit: edit)
          .then((saved) {
            if (saved && mounted) widget.onClose();
          }),
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

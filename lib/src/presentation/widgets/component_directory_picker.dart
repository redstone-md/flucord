import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/message_component.dart';
import '../../theme/flucord_theme.dart';

/// One thing a directory select can resolve to.
final class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    required this.label,
    this.detail = '',
  });

  final String id;
  final String label;
  final String detail;
}

/// Resolves a user, role, channel or mentionable select against the workspace.
///
/// Discord's own client shows the server's directory here rather than a list
/// the application supplied — these selects carry no options, only a type — so
/// the picker is built from what the client already knows about the space.
abstract final class ComponentDirectory {
  /// Everything [component] may be answered with, given [workspace] and the
  /// space the message is in.
  ///
  /// A mentionable select takes both members and roles, which is why the two
  /// are concatenated rather than chosen between.
  static List<DirectoryEntry> entriesFor(
    MessageComponent component, {
    required ChatWorkspace workspace,
    required String spaceId,
  }) => switch (component.type) {
    5 => _members(workspace),
    6 => _roles(workspace, spaceId),
    7 => [..._members(workspace), ..._roles(workspace, spaceId)],
    8 => _channels(workspace, spaceId),
    _ => const [],
  };

  static List<DirectoryEntry> _members(ChatWorkspace workspace) => [
    for (final member in workspace.members)
      DirectoryEntry(
        id: member.id,
        label: member.displayName,
        detail: member.role,
      ),
  ];

  static List<DirectoryEntry> _roles(ChatWorkspace workspace, String spaceId) =>
      [
        for (final role in workspace.roles)
          if (role.spaceId == spaceId)
            DirectoryEntry(id: role.id, label: role.name),
      ];

  static List<DirectoryEntry> _channels(
    ChatWorkspace workspace,
    String spaceId,
  ) {
    return [
      for (final channel in workspace.channels)
        if (channel.spaceId == spaceId)
          DirectoryEntry(
            id: channel.id,
            label: channel.name,
            detail: switch (channel.kind) {
              ChannelKind.voice => 'Voice',
              ChannelKind.forum => 'Forum',
              ChannelKind.media => 'Media',
              ChannelKind.text => channel.isThread ? 'Thread' : 'Text',
            },
          ),
    ];
  }
}

/// The dialog that answers a directory select.
class ComponentDirectoryPicker extends StatefulWidget {
  const ComponentDirectoryPicker({
    required this.title,
    required this.entries,
    required this.maxValues,
    super.key,
  });

  final String title;
  final List<DirectoryEntry> entries;

  /// How many may be chosen. Discord enforces it server-side too, but a form
  /// that lets you pick five when one is allowed only produces a rejection.
  final int maxValues;

  /// Returns the chosen ids, or null when the picker was closed.
  static Future<List<String>?> show(
    BuildContext context, {
    required String title,
    required List<DirectoryEntry> entries,
    int maxValues = 1,
  }) => showDialog<List<String>>(
    context: context,
    builder: (_) => ComponentDirectoryPicker(
      title: title,
      entries: entries,
      maxValues: maxValues,
    ),
  );

  @override
  State<ComponentDirectoryPicker> createState() =>
      _ComponentDirectoryPickerState();
}

class _ComponentDirectoryPickerState extends State<ComponentDirectoryPicker> {
  final Set<String> _chosen = {};
  String _query = '';

  List<DirectoryEntry> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.entries;
    return widget.entries
        .where(
          (entry) =>
              entry.label.toLowerCase().contains(query) ||
              entry.detail.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  void _toggle(String id) {
    setState(() {
      if (_chosen.remove(id)) return;
      // Choosing past the limit replaces the oldest rather than refusing the
      // tap: a single-value select is the common case and swapping is what a
      // user means by tapping a second row.
      if (_chosen.length >= widget.maxValues && _chosen.isNotEmpty) {
        _chosen.remove(_chosen.first);
      }
      _chosen.add(id);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('directory-picker'),
    title: Text(widget.title.isEmpty ? 'Choose' : widget.title),
    content: SizedBox(
      width: 360,
      height: 380,
      child: Column(
        children: [
          TextField(
            key: const ValueKey('directory-search'),
            autofocus: true,
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search',
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _visible.isEmpty
                ? Center(
                    child: Text(
                      'Nothing matches that.',
                      key: const ValueKey('directory-empty'),
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _visible.length,
                    itemBuilder: (context, index) {
                      final entry = _visible[index];
                      return CheckboxListTile(
                        key: ValueKey('directory-entry-${entry.id}'),
                        dense: true,
                        value: _chosen.contains(entry.id),
                        title: Text(entry.label),
                        subtitle: entry.detail.isEmpty
                            ? null
                            : Text(entry.detail),
                        onChanged: (_) => _toggle(entry.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('directory-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('directory-confirm'),
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.of(context).pop(_chosen.toList(growable: false)),
        child: const Text('Choose'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import '../profile_image_picker.dart';
import 'direct_message_views.dart';
import 'flucord_button.dart';
import 'flucord_dialog.dart';
import 'member_avatar.dart';

/// A group DM's name, picture and people. The owner can also remove people.
///
/// The picture and the people change at once; the name changes on Save.
/// Each callback answers whether Discord took the change.
class GroupDirectMessageSettingsDialog extends StatefulWidget {
  const GroupDirectMessageSettingsDialog({
    required this.channel,
    required this.recipients,
    required this.isOwner,
    required this.onRename,
    required this.onSetIcon,
    required this.onRemove,
    this.imagePicker = const NativeProfileImagePicker(),
    super.key,
  });

  static const _iconSize = 64.0;

  final ConversationChannel channel;

  /// The people in the group, this account aside.
  final List<Member> recipients;
  final bool isOwner;
  final Future<bool> Function(String name) onRename;

  /// Sets the picture to a data URI, or removes it with null.
  final Future<bool> Function(String? iconDataUri) onSetIcon;
  final Future<bool> Function(String userId) onRemove;
  final ProfileImagePicker imagePicker;

  @override
  State<GroupDirectMessageSettingsDialog> createState() =>
      _GroupDirectMessageSettingsDialogState();
}

class _GroupDirectMessageSettingsDialogState
    extends State<GroupDirectMessageSettingsDialog> {
  late final _name = TextEditingController(text: widget.channel.name);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Runs [change] and shows [failure] when Discord refuses it.
  Future<bool> _run(Future<bool> Function() change, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final done = await change();
    if (mounted) {
      setState(() {
        _busy = false;
        if (!done) _error = failure;
      });
    }
    return done;
  }

  Future<void> _pickIcon() async {
    final ProfileImageSelection? picked;
    try {
      picked = await widget.imagePicker.pick();
    } on ProfileImageRejected catch (rejection) {
      setState(() => _error = rejection.message);
      return;
    }
    if (picked == null || !mounted) return;
    await _run(
      () => widget.onSetIcon(picked!.dataUri),
      'The icon could not be changed.',
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final navigator = Navigator.of(context);
    if (name != widget.channel.name &&
        !await _run(
          () => widget.onRename(name),
          'The name could not be saved.',
        )) {
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final channel = widget.channel;
    return FlucordDialog(
      title: const Text('Group settings'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GroupDirectMessageAvatar(
                  channel: channel,
                  size: GroupDirectMessageSettingsDialog._iconSize,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FlucordButton(
                        key: const ValueKey('group-dm-change-icon'),
                        label: 'Change icon',
                        onPressed: _busy ? null : _pickIcon,
                      ),
                      if (channel.iconUrl != null)
                        FlucordButton(
                          key: const ValueKey('group-dm-remove-icon'),
                          label: 'Remove icon',
                          kind: FlucordButtonKind.ghost,
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => widget.onSetIcon(null),
                                  'The icon could not be removed.',
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('group-dm-name'),
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Group name'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(
              'Members',
              style: FlucordTextRole.label.strong.copyWith(
                color: surfaces.muted,
              ),
            ),
            for (final person in widget.recipients)
              ListTile(
                key: ValueKey('group-dm-member-${person.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: MemberAvatar(member: person, size: 30),
                title: Text(
                  person.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: widget.isOwner
                    ? FlucordButton(
                        key: ValueKey('group-dm-remove-${person.id}'),
                        label: 'Remove',
                        kind: FlucordButtonKind.ghost,
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => widget.onRemove(person.id),
                                '${person.displayName} could not be removed.',
                              ),
                      )
                    : null,
              ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: surfaces.danger)),
            ],
          ],
        ),
      ),
      confirm: FlucordDialogConfirm(
        key: const ValueKey('group-dm-save'),
        label: 'Save',
        onPressed: _busy || _name.text.trim().isEmpty ? null : _save,
      ),
    );
  }
}

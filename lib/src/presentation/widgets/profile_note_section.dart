import 'package:flutter/material.dart';

import '../../application/member_profile_controller.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// The private note this account keeps on the user, editable in place.
///
/// The field is always shown: the note is the one section the account owns,
/// and hiding it for being empty is how nobody ever learns it exists.
/// Saving a blank note removes it, which is the only way a note is removed.
class ProfileNoteSection extends StatefulWidget {
  const ProfileNoteSection({required this.controller, super.key});

  final MemberProfileController controller;

  @override
  State<ProfileNoteSection> createState() => _ProfileNoteSectionState();
}

class _ProfileNoteSectionState extends State<ProfileNoteSection> {
  late final TextEditingController _field;
  bool _dirty = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = widget.controller.openUserId;
    _field = TextEditingController(text: widget.controller.note ?? '');
    widget.controller.addListener(_followNote);
  }

  @override
  void didUpdateWidget(covariant ProfileNoteSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_followNote);
    widget.controller.addListener(_followNote);
    _followNote();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_followNote);
    _field.dispose();
    super.dispose();
  }

  /// Shows the newest note while the field is untouched, so a save never
  /// writes back text older than the note. An edit in progress is kept; its
  /// Discard shows the newest note. Another user starts from their own note.
  void _followNote() {
    final controller = widget.controller;
    final otherUser = controller.openUserId != _userId;
    if (_dirty && !otherUser) return;
    _userId = controller.openUserId;
    _dirty = false;
    final note = controller.note ?? '';
    if (_field.text != note) _field.text = note;
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.controller, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final controller = widget.controller;
    return Column(
      key: const ValueKey('profile-note-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('profile-note-field'),
          controller: _field,
          enabled: controller.isSupported && !controller.noteSaving,
          maxLength: 256,
          maxLines: 3,
          minLines: 1,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: controller.isSupported
                ? 'Click to add a note'
                : 'Notes need a signed-in account',
          ),
          style: FlucordTextRole.label.style,
        ),
        if (controller.noteRefused)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Discord did not take that note.',
              key: const ValueKey('profile-note-refused'),
              style: FlucordTextRole.caption.style.copyWith(
                color: context.surfaces.errorText,
              ),
            ),
          ),
        if (_dirty && controller.isSupported)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TextButton(
                  key: const ValueKey('profile-note-discard'),
                  onPressed: () {
                    _field.text = controller.note ?? '';
                    setState(() => _dirty = false);
                  },
                  child: const Text('Discard'),
                ),
                FilledButton(
                  key: const ValueKey('profile-note-save'),
                  onPressed: controller.noteSaving
                      ? null
                      : () async {
                          await controller.saveNote(_field.text);
                          if (mounted && !controller.noteRefused) {
                            setState(() => _dirty = false);
                          }
                        },
                  child: Text(controller.noteSaving ? 'Saving…' : 'Save note'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

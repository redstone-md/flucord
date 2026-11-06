import 'package:flutter/material.dart';

import 'flucord_dialog.dart';
import 'user_profile_controls.dart';

/// What the folder settings dialog saves.
typedef FolderSettings = ({String? name, int? colour});

/// A server folder's name and colour. Answers the new [FolderSettings] on
/// Save, or null when closed.
class FolderSettingsDialog extends StatefulWidget {
  const FolderSettingsDialog({this.name, this.colour, super.key});

  final String? name;

  /// 0xRRGGBB, or null for the default colour.
  final int? colour;

  @override
  State<FolderSettingsDialog> createState() => _FolderSettingsDialogState();
}

class _FolderSettingsDialogState extends State<FolderSettingsDialog> {
  late final _name = TextEditingController(text: widget.name);
  late int? _colour = widget.colour;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(
    context,
  ).pop<FolderSettings>((name: _name.text.trim(), colour: _colour));

  @override
  Widget build(BuildContext context) => FlucordDialog(
    title: const Text('Folder settings'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('folder-name'),
            controller: _name,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Folder name'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          ProfileColourPicker(
            label: 'Folder colour',
            keyPrefix: 'folder-colour',
            value: _colour,
            onChanged: (colour) => setState(() => _colour = colour),
          ),
        ],
      ),
    ),
    confirm: FlucordDialogConfirm(
      key: const ValueKey('folder-save'),
      label: 'Save',
      onPressed: _save,
    ),
  );
}
